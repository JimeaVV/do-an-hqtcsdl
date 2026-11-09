"""
ai/db_helper.py
Module tiện ích kết nối cơ sở dữ liệu SQL Server cho các tác vụ AI và dữ liệu.
Đọc cấu hình từ file .env.
"""

import os
import pyodbc
from dotenv import load_dotenv

# Tải cấu hình từ .env
load_dotenv()

def get_connection_string():
    """Tạo chuỗi kết nối tới SQL Server dựa trên biến môi trường."""
    driver = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")
    server = os.getenv("DB_SERVER", r"localhost\SQLEXPRESS")
    database = os.getenv("DB_NAME", "ShopDB")
    trusted_connection = os.getenv("DB_TRUSTED_CONNECTION", "yes")
    trust_cert = os.getenv("DB_TRUST_SERVER_CERTIFICATE", "yes")

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"Trusted_Connection={trusted_connection};"
        f"TrustServerCertificate={trust_cert};"
    )
    return conn_str

def get_connection(autocommit=True):
    """Mở và trả về kết nối pyodbc."""
    conn_str = get_connection_string()
    return pyodbc.connect(conn_str, autocommit=autocommit)

