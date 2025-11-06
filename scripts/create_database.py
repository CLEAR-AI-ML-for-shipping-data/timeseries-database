from datetime import datetime

from geoalchemy2 import Geometry
from shapely import Point
from sqlalchemy import ForeignKey, String, create_engine, text
from sqlalchemy.orm import (DeclarativeBase, Mapped, mapped_column,
                            relationship, sessionmaker)


class Base(DeclarativeBase):
    pass


class Ship(Base):
    __tablename__ = "ships"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    mmsi: Mapped[str] = mapped_column(String(20), unique=True)

    positions: Mapped[list["Position"]] = relationship(back_populates="ship")


class Position(Base):
    __tablename__ = "positions"
    position_id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)

    position: Mapped[Geometry] = mapped_column(
        Geometry(geometry_type="POINT", srid=4326)
    )
    ship_id = mapped_column(ForeignKey("ships.id"))
    timestamp: Mapped[datetime]
    nav_status: Mapped[str]

    ship: Mapped[Ship] = relationship(back_populates="positions")


class ClearAIS_DB:
    def __init__(self, database_url) -> None:
        self.engine = create_engine(database_url, echo=True)
        self.Session = sessionmaker(self.engine)

    def get_session(self):
        return self.Session()

    def create_tables(self, drop_existing=True):
        if drop_existing:
            Base.metadata.drop_all(self.engine)
        with self.Session() as session:
            # session.execute(text(f"CREATE SCHEMA IF NOT EXISTS {POSTGRES_SCHEMA}"))
            # session.commit()
            Base.metadata.create_all(self.engine)


if __name__ == "__main__":
    POSTGRES_DB = "experiment"
    POSTGRES_USER = "clear"
    POSTGRES_PASSWORD = "clear"
    POSTGRES_PORT = 5432
    POSTGRES_HOST = "localhost"
    database_url = f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

    database = ClearAIS_DB(database_url)
    with database.Session() as session:
        session.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))
        session.commit()
    database.create_tables(drop_existing=True)

