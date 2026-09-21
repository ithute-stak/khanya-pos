from uuid import uuid4

from app.security.tokens import (
    create_access_token,
    decode_token,
    hash_password,
    verify_password,
)


def test_password_hash_round_trip() -> None:
    hashed = hash_password("very-secure-password")
    assert hashed != "very-secure-password"
    assert verify_password("very-secure-password", hashed)
    assert not verify_password("wrong-password", hashed)


def test_access_token_contains_user_and_session() -> None:
    user_id = uuid4()
    session_id = uuid4()
    token = create_access_token(user_id, session_id)
    payload = decode_token(token, "access")
    assert payload["sub"] == str(user_id)
    assert payload["sid"] == str(session_id)
