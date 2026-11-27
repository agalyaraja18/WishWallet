from __future__ import annotations

import ipaddress
import json
import re
import secrets
import socket
import ssl
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from http.client import HTTPConnection, HTTPSConnection
from io import BytesIO
from urllib.parse import urljoin, urlsplit

import cloudinary
import cloudinary.uploader
from bs4 import BeautifulSoup
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from pydantic import BaseModel, ConfigDict, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from pwdlib import PasswordHash
from sqlalchemy import ForeignKey, String, create_engine, inspect, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    mapped_column,
    relationship,
    selectinload,
    sessionmaker,
)


class Settings(BaseSettings):
    database_url: str = "sqlite:///./wishwallet.db"
    jwt_secret: str = "development-only-change-this-secret"
    jwt_expire_minutes: int = 10080
    cloudinary_cloud_name: str = ""
    cloudinary_api_key: str = ""
    cloudinary_api_secret: str = ""
    allowed_origins: str = "http://localhost:*"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, connect_args=connect_args, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
password_hash = PasswordHash.recommended()
bearer = HTTPBearer(auto_error=False)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    recovery_code_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    categories: Mapped[list[Category]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    user: Mapped[User] = relationship(back_populates="categories")
    wishes: Mapped[list[Wish]] = relationship(
        back_populates="category", cascade="all, delete-orphan", lazy="selectin"
    )


class Wish(Base):
    __tablename__ = "wishes"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(240))
    url: Mapped[str] = mapped_column(String(2048))
    price: Mapped[float | None]
    image_url: Mapped[str | None] = mapped_column(String(2048))
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id", ondelete="CASCADE"))
    category: Mapped[Category] = relationship(back_populates="wishes")


class Credentials(BaseModel):
    user_id: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=8, max_length=128)


class Registration(Credentials):
    recovery_code: str = Field(pattern=r"^[A-Fa-f0-9]{32}$")


class ResetCredentials(BaseModel):
    user_id: str = Field(min_length=1, max_length=80)
    recovery_code: str = Field(pattern=r"^[A-Fa-f0-9]{32}$")
    new_recovery_code: str = Field(pattern=r"^[A-Fa-f0-9]{32}$")
    password: str = Field(min_length=8, max_length=128)


class ChangeUserId(BaseModel):
    user_id: str = Field(min_length=1, max_length=80)
    current_password: str = Field(min_length=8, max_length=128)


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class WishCreate(BaseModel):
    name: str = Field(min_length=1, max_length=240)
    url: str = Field(min_length=8, max_length=2048)
    category_id: int
    price: float | None = Field(default=None, ge=0)
    image_url: str | None = Field(default=None, max_length=2048)


class WishOut(BaseModel):
    id: int
    name: str
    url: str
    category_id: int
    price: float | None
    image_url: str | None
    model_config = ConfigDict(from_attributes=True)


class CategoryOut(BaseModel):
    id: int
    name: str
    wishes: list[WishOut]
    model_config = ConfigDict(from_attributes=True)


class ScanRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2048)


class ScanResult(BaseModel):
    name: str
    price: float | None
    image_url: str | None


Base.metadata.create_all(engine)
if "recovery_code_hash" not in {
    column["name"] for column in inspect(engine).get_columns("users")
}:
    with engine.begin() as connection:
        connection.execute(
            text("ALTER TABLE users ADD COLUMN recovery_code_hash VARCHAR(255)")
        )

if all(
    (
        settings.cloudinary_cloud_name,
        settings.cloudinary_api_key,
        settings.cloudinary_api_secret,
    )
):
    cloudinary.config(
        cloud_name=settings.cloudinary_cloud_name,
        api_key=settings.cloudinary_api_key,
        api_secret=settings.cloudinary_api_secret,
        secure=True,
    )

app = FastAPI(title="WishWallet API", version="1.0.0")
origins = [origin.strip() for origin in settings.allowed_origins.split(",") if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@contextmanager
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_token(user: User) -> str:
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    return jwt.encode(
        {"sub": str(user.id), "exp": expires},
        settings.jwt_secret,
        algorithm="HS256",
    )


def _new_recovery_code() -> str:
    return secrets.token_hex(16).upper()


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
):
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Sign in required")
    try:
        payload = jwt.decode(credentials.credentials, settings.jwt_secret, algorithms=["HS256"])
        user_id = int(payload["sub"])
    except (JWTError, KeyError, TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session")
    with get_db() as db:
        user = db.get(User, user_id)
        if user is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account not found")
        db.expunge(user)
        return user


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/auth/register", status_code=status.HTTP_201_CREATED)
def register(body: Registration):
    with get_db() as db:
        if db.scalar(select(User).where(User.user_id == body.user_id)):
            raise HTTPException(status_code=409, detail="User ID already exists")
        user = User(
            user_id=body.user_id,
            password_hash=password_hash.hash(body.password),
            recovery_code_hash=password_hash.hash(body.recovery_code.upper()),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        return {
            "access_token": create_token(user),
            "token_type": "bearer",
            "user_id": user.user_id,
        }


@app.post("/api/auth/login")
def login(body: Credentials):
    with get_db() as db:
        user = db.scalar(select(User).where(User.user_id == body.user_id))
        if user is None or not password_hash.verify(body.password, user.password_hash):
            raise HTTPException(status_code=401, detail="Invalid user ID or password")
        recovery_code = None
        if user.recovery_code_hash is None:
            recovery_code = _new_recovery_code()
            user.recovery_code_hash = password_hash.hash(recovery_code)
            db.commit()
        return {
            "access_token": create_token(user),
            "token_type": "bearer",
            "user_id": user.user_id,
            "recovery_code": recovery_code,
        }


@app.post("/api/auth/recover-password")
def recover_password(body: ResetCredentials):
    with get_db() as db:
        saved = db.scalar(select(User).where(User.user_id == body.user_id))
        if (
            saved is None
            or saved.recovery_code_hash is None
            or not password_hash.verify(
                body.recovery_code.upper(), saved.recovery_code_hash
            )
        ):
            raise HTTPException(
                status_code=400,
                detail="User ID or recovery code is incorrect",
            )
        saved.password_hash = password_hash.hash(body.password)
        saved.recovery_code_hash = password_hash.hash(body.new_recovery_code.upper())
        db.commit()
    return {"status": "updated"}


@app.put("/api/auth/user-id")
def change_user_id(body: ChangeUserId, user: User = Depends(current_user)):
    new_user_id = body.user_id.strip()
    if not new_user_id:
        raise HTTPException(status_code=422, detail="Username cannot be empty")
    with get_db() as db:
        saved = db.get(User, user.id)
        if saved is None:
            raise HTTPException(status_code=404, detail="Account not found")
        if not password_hash.verify(body.current_password, saved.password_hash):
            raise HTTPException(status_code=400, detail="Current password is incorrect")
        duplicate = db.scalar(
            select(User).where(User.user_id == new_user_id, User.id != user.id)
        )
        if duplicate:
            raise HTTPException(status_code=409, detail="Username already exists")
        saved.user_id = new_user_id
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Username already exists")
        return {"user_id": saved.user_id}


@app.post("/api/auth/reset-password")
def reset_password(
    body: ResetCredentials, user: User = Depends(current_user)
):
    if user.user_id != body.user_id:
        raise HTTPException(status_code=403, detail="This account does not match your session")
    with get_db() as db:
        saved = db.get(User, user.id)
        if saved is None or not password_hash.verify(body.current_password, saved.password_hash):
            raise HTTPException(status_code=400, detail="Current password is incorrect")
        saved.password_hash = password_hash.hash(body.password)
        db.commit()
    return {"status": "updated"}


@app.delete("/api/auth/account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(user: User = Depends(current_user)):
    with get_db() as db:
        saved = db.get(User, user.id)
        if saved is None:
            raise HTTPException(status_code=404, detail="Account not found")
        db.delete(saved)
        db.commit()


@app.get("/api/categories", response_model=list[CategoryOut])
def list_categories(user: User = Depends(current_user)):
    with get_db() as db:
        return db.scalars(
            select(Category)
            .options(selectinload(Category.wishes))
            .where(Category.user_id == user.id)
            .order_by(Category.id)
        ).all()


@app.post("/api/categories", response_model=CategoryOut, status_code=201)
def create_category(body: CategoryCreate, user: User = Depends(current_user)):
    with get_db() as db:
        exists = db.scalar(
            select(Category).where(
                Category.user_id == user.id,
                Category.name.ilike(body.name.strip()),
            )
        )
        if exists:
            raise HTTPException(status_code=409, detail="Category already exists")
        category = Category(name=body.name.strip(), user_id=user.id)
        db.add(category)
        db.commit()
        return db.scalar(
            select(Category)
            .options(selectinload(Category.wishes))
            .where(Category.id == category.id)
        )


@app.delete("/api/categories/{category_id}", status_code=204)
def delete_category(category_id: int, user: User = Depends(current_user)):
    with get_db() as db:
        category = db.scalar(
            select(Category).where(
                Category.id == category_id,
                Category.user_id == user.id,
            )
        )
        if category is None:
            raise HTTPException(status_code=404, detail="Category not found")
        db.delete(category)
        db.commit()


@app.post("/api/wishes", response_model=WishOut, status_code=201)
def create_wish(body: WishCreate, user: User = Depends(current_user)):
    with get_db() as db:
        category = db.scalar(
            select(Category).where(
                Category.id == body.category_id,
                Category.user_id == user.id,
            )
        )
        if category is None:
            raise HTTPException(status_code=404, detail="Category not found")
        wish = Wish(
            name=body.name.strip(),
            url=body.url,
            price=body.price,
            image_url=body.image_url,
            category_id=category.id,
        )
        db.add(wish)
        db.commit()
        db.refresh(wish)
        return wish


@app.delete("/api/wishes/{wish_id}", status_code=204)
def delete_wish(wish_id: int, user: User = Depends(current_user)):
    with get_db() as db:
        wish = db.scalar(
            select(Wish)
            .join(Category)
            .where(Wish.id == wish_id, Category.user_id == user.id)
        )
        if wish is None:
            raise HTTPException(status_code=404, detail="Wish not found")
        db.delete(wish)
        db.commit()


def _validated_target(url: str):
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Only public http and https product links are supported")
    if parsed.username or parsed.password:
        raise ValueError("Links containing credentials are not supported")
    host = parsed.hostname.encode("idna").decode("ascii")
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        addresses = {
            ipaddress.ip_address(result[4][0])
            for result in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        }
    except (socket.gaierror, ValueError):
        raise ValueError("The product website could not be resolved")
    if not addresses or any(not address.is_global for address in addresses):
        raise ValueError("Only publicly reachable product websites can be scanned")
    return parsed, host, port, sorted(addresses, key=lambda address: address.version)[0]


def _safe_get(url: str, max_bytes: int):
    current_url = url
    for _ in range(5):
        parsed, host, port, address = _validated_target(current_url)
        connection_type = HTTPSConnection if parsed.scheme == "https" else HTTPConnection
        connection = connection_type(host, port, timeout=8)
        try:
            raw_socket = socket.create_connection((str(address), port), timeout=8)
            if parsed.scheme == "https":
                raw_socket = ssl.create_default_context().wrap_socket(
                    raw_socket, server_hostname=host
                )
            connection.sock = raw_socket
            path = parsed.path or "/"
            if parsed.query:
                path += f"?{parsed.query}"
            connection.request(
                "GET",
                path,
                headers={
                    "Host": host,
                    "User-Agent": "WishWallet/1.0 (+product metadata preview)",
                    "Accept": "text/html,image/*;q=0.8",
                },
            )
            response = connection.getresponse()
            if response.status in {301, 302, 303, 307, 308}:
                location = response.getheader("Location")
                if not location:
                    raise ValueError("The store returned an invalid redirect")
                current_url = urljoin(current_url, location)
                continue
            if response.status < 200 or response.status >= 300:
                raise ValueError(f"The store responded with HTTP {response.status}")
            content_length = response.getheader("Content-Length")
            if content_length and int(content_length) > max_bytes:
                raise ValueError("The store page is too large to scan")
            body = response.read(max_bytes + 1)
            if len(body) > max_bytes:
                raise ValueError("The store page is too large to scan")
            return body, response.getheader("Content-Type", ""), current_url
        finally:
            connection.close()
    raise ValueError("The store redirected too many times")


def _metadata_price(soup: BeautifulSoup) -> float | None:
    candidates: list[str] = []
    for tag in soup.find_all("meta"):
        key = (tag.get("property") or tag.get("name") or "").lower()
        if key in {
            "product:price:amount",
            "og:price:amount",
            "price",
            "twitter:data1",
        }:
            candidates.append(tag.get("content", ""))
    for tag in soup.select('[itemprop="price"]'):
        candidates.extend([tag.get("content", ""), tag.get_text(" ", strip=True)])
    for script in soup.select('script[type="application/ld+json"]'):
        try:
            data = json.loads(script.string or script.get_text())
        except (json.JSONDecodeError, TypeError):
            continue
        pending = [data]
        while pending:
            item = pending.pop()
            if isinstance(item, dict):
                for key in ("price", "lowPrice", "highPrice"):
                    value = item.get(key)
                    if isinstance(value, (str, int, float)):
                        candidates.append(str(value))
                pending.extend(item.values())
            elif isinstance(item, list):
                pending.extend(item)
    for candidate in candidates:
        match = re.search(r"\d[\d.,\s]*\d|\d", candidate)
        if not match:
            continue
        cleaned = match.group(0).replace(" ", "")
        if not cleaned:
            continue
        if "," in cleaned and "." in cleaned:
            decimal_separator = "," if cleaned.rfind(",") > cleaned.rfind(".") else "."
            grouping_separator = "." if decimal_separator == "," else ","
            cleaned = cleaned.replace(grouping_separator, "")
            if decimal_separator == ",":
                cleaned = cleaned.replace(",", ".")
        elif "," in cleaned:
            last_group = cleaned.rsplit(",", 1)[1]
            if len(last_group) == 3 and all(
                len(group) == 3 for group in cleaned.split(",")[1:]
            ):
                cleaned = cleaned.replace(",", "")
            else:
                cleaned = cleaned.replace(",", ".")
        try:
            price = float(cleaned)
            if price >= 0:
                return price
        except ValueError:
            continue
    return None


@app.post("/api/metadata/scan", response_model=ScanResult)
def scan_metadata(body: ScanRequest, _user: User = Depends(current_user)):
    try:
        html, content_type, final_url = _safe_get(body.url, 2_000_000)
        if "html" not in content_type.lower():
            raise ValueError("That link does not appear to be a product page")
        soup = BeautifulSoup(html, "html.parser")
        title_tag = soup.find("meta", property="og:title")
        image_tag = soup.find("meta", property="og:image")
        name = (
            (title_tag.get("content") if title_tag else None)
            or (soup.title.get_text(" ", strip=True) if soup.title else None)
            or urlsplit(final_url).hostname
            or "Saved product"
        )
        image_url = (
            urljoin(final_url, image_tag.get("content", ""))
            if image_tag and image_tag.get("content")
            else None
        )
        if (
            image_url
            and settings.cloudinary_cloud_name
            and settings.cloudinary_api_key
            and settings.cloudinary_api_secret
        ):
            image, image_type, _ = _safe_get(image_url, 5_000_000)
            if not image_type.lower().startswith("image/"):
                image_url = None
            else:
                result = cloudinary.uploader.upload(
                    BytesIO(image),
                    folder="wishwallet",
                    resource_type="image",
                )
                image_url = result["secure_url"]
        return ScanResult(
            name=name[:240],
            price=_metadata_price(soup),
            image_url=image_url,
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error))
    except (OSError, ssl.SSLError, TimeoutError) as error:
        raise HTTPException(status_code=502, detail=f"Could not read the product page: {error}")
