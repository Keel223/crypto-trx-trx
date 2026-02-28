import os
import random
import sqlite3
import string
from datetime import datetime, timedelta
from flask import Flask, redirect, render_template_string, request, session, url_for

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "ton-faucet-casino-secret")
DB_PATH = os.environ.get("DB_PATH", "ton_faucet.db")

CONFIG = {
    "currency": "TON",
    "faucet_reward": 0.03,
    "faucet_interval_hours": 1,
    "min_bet": 0.01,
    "max_bet": 500.0,
    "ref_percent": 0.03,
    "min_withdraw": 1.0,
    "min_deposit": 0.5,
    "mining_price_per_th": 10.0,
    "mining_roi_days": 100,
}

GAMES = {
    "coinflip": {"name": "Coin Flip", "win_chance": 0.49, "multiplier": 1.95},
    "dice": {"name": "Dice 1-6", "win_chance": 1 / 6, "multiplier": 5.7},
    "roulette": {"name": "Roulette Red/Black", "win_chance": 0.485, "multiplier": 1.9},
    "slots": {"name": "Slots", "win_chance": 0.25, "multiplier": 3.6},
    "crash": {"name": "Crash", "win_chance": 0.4, "multiplier": 2.3},
    "hi_lo": {"name": "Hi / Lo", "win_chance": 0.48, "multiplier": 2.0},
    "blackjack": {"name": "Blackjack", "win_chance": 0.45, "multiplier": 2.15},
}

BASE_HTML = """
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TON Faucet & Casino</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; background: #101522; color: #e8eefc; }
    nav { background: #1d2841; padding: 12px; display: flex; gap: 12px; flex-wrap: wrap; }
    nav a { color: #fff; text-decoration: none; background: #2d3f68; padding: 8px 12px; border-radius: 8px; }
    nav .right { margin-left: auto; }
    .container { max-width: 1024px; margin: 20px auto; padding: 0 12px; }
    .card { background: #1b2338; padding: 16px; border-radius: 12px; margin-bottom: 14px; }
    input, button, select { padding: 8px; border-radius: 8px; border: none; }
    button { cursor: pointer; background: #4d73ff; color: #fff; }
    table { width: 100%; border-collapse: collapse; }
    td, th { border-bottom: 1px solid #2e3a58; padding: 8px; text-align: left; }
    .msg { padding: 10px; border-radius: 10px; background: #2c3a5b; margin-bottom: 14px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit,minmax(220px,1fr)); gap: 10px; }
  </style>
</head>
<body>
<nav>
  <a href="{{ url_for('dashboard') }}">Дашборд</a>
  <a href="{{ url_for('faucet') }}">Кран TON</a>
  <a href="{{ url_for('casino') }}">Казино (7 игр)</a>
  <a href="{{ url_for('mining') }}">Майнинг</a>
  <a href="{{ url_for('referrals') }}">Рефералы</a>
  <a href="{{ url_for('wallet_page') }}">Пополнение/Вывод</a>
  {% if session.get('wallet') %}
  <a class="right" href="{{ url_for('logout') }}">Выход ({{ session.get('wallet') }})</a>
  {% endif %}
</nav>
<div class="container">
  {% if message %}<div class="msg">{{ message }}</div>{% endif %}
  {{ body|safe }}
</div>
</body>
</html>
"""


def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = db()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            wallet TEXT UNIQUE,
            balance REAL DEFAULT 0,
            total_bets REAL DEFAULT 0,
            total_wins REAL DEFAULT 0,
            total_claimed REAL DEFAULT 0,
            referral_code TEXT UNIQUE,
            referred_by INTEGER,
            referral_earnings REAL DEFAULT 0,
            mining_th REAL DEFAULT 0,
            last_claim TEXT,
            last_mining_claim TEXT,
            created_at TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            kind TEXT,
            amount REAL,
            note TEXT,
            created_at TEXT
        )
        """
    )
    conn.commit()
    conn.close()


def now_iso():
    return datetime.utcnow().isoformat()


def current_user():
    wallet = session.get("wallet")
    if not wallet:
        return None
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE wallet = ?", (wallet,)).fetchone()
    conn.close()
    return user


def login_required():
    return session.get("wallet") is not None


def gen_ref_code(wallet):
    prefix = "".join(ch for ch in wallet if ch.isalnum())[:4].upper() or "TON"
    token = "".join(random.choices(string.ascii_uppercase + string.digits, k=6))
    return f"{prefix}{token}"


def render(body, message=""):
    return render_template_string(BASE_HTML, body=body, message=message)


def income_boost(user):
    return min(1 + user["total_bets"] / 100.0, 4.0)


@app.route("/", methods=["GET", "POST"])
def dashboard():
    if request.method == "POST":
        wallet = request.form.get("wallet", "").strip()
        ref = request.form.get("ref", "").strip().upper()
        if not wallet:
            return render("<div class='card'>Введите FaucetPay wallet.</div>", "Ошибка: wallet пустой")

        conn = db()
        cur = conn.cursor()
        user = cur.execute("SELECT * FROM users WHERE wallet = ?", (wallet,)).fetchone()
        if not user:
            referred_by = None
            if ref:
                ref_owner = cur.execute("SELECT id FROM users WHERE referral_code = ?", (ref,)).fetchone()
                referred_by = ref_owner["id"] if ref_owner else None
            code = gen_ref_code(wallet)
            cur.execute(
                """
                INSERT INTO users (wallet, balance, referral_code, referred_by, last_mining_claim, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (wallet, 1.0, code, referred_by, now_iso(), now_iso()),
            )
            conn.commit()
        conn.close()
        session["wallet"] = wallet
        return redirect(url_for("dashboard"))

    user = current_user()
    if not user:
        ref = request.args.get("ref", "")
        body = f"""
        <div class='card'>
          <h2>TON Crypto Faucet + Casino</h2>
          <p>Собирай TON раз в час, играй в 7 казино-игр, используй майнинг и реферальную систему.</p>
          <form method='post'>
            <input name='wallet' placeholder='Ваш FaucetPay wallet' required>
            <input name='ref' placeholder='Реф-код (необязательно)' value='{ref}'>
            <button type='submit'>Войти</button>
          </form>
        </div>
        """
        return render(body)

    boost = income_boost(user)
    next_claim = "сейчас"
    if user["last_claim"]:
        unlock = datetime.fromisoformat(user["last_claim"]) + timedelta(hours=CONFIG["faucet_interval_hours"])
        if unlock > datetime.utcnow():
            next_claim = str(unlock - datetime.utcnow()).split(".")[0]

    body = f"""
    <div class='grid'>
      <div class='card'><h3>Баланс</h3><p>{user['balance']:.6f} {CONFIG['currency']}</p></div>
      <div class='card'><h3>Буст дохода</h3><p>x{boost:.2f}</p><small>Зависит от общей суммы ставок.</small></div>
      <div class='card'><h3>Следующий кран</h3><p>{next_claim}</p></div>
      <div class='card'><h3>Мощность майнинга</h3><p>{user['mining_th']:.2f} TH/s</p></div>
    </div>
    """
    return render(body)


@app.route("/faucet", methods=["GET", "POST"])
def faucet():
    if not login_required():
        return redirect(url_for("dashboard"))
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE wallet = ?", (session["wallet"],)).fetchone()
    message = ""

    if request.method == "POST":
        can_claim = True
        if user["last_claim"]:
            unlock = datetime.fromisoformat(user["last_claim"]) + timedelta(hours=1)
            can_claim = datetime.utcnow() >= unlock
        if can_claim:
            reward = CONFIG["faucet_reward"] * income_boost(user)
            conn.execute(
                "UPDATE users SET balance = balance + ?, total_claimed = total_claimed + ?, last_claim = ? WHERE id = ?",
                (reward, reward, now_iso(), user["id"]),
            )
            conn.execute(
                "INSERT INTO transactions (user_id, kind, amount, note, created_at) VALUES (?, 'faucet_claim', ?, ?, ?)",
                (user["id"], reward, "Hourly TON faucet", now_iso()),
            )
            conn.commit()
            message = f"Получено {reward:.6f} TON"
        else:
            message = "Ещё рано, кран доступен 1 раз в час"
        user = conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()

    wait = "Доступно сейчас"
    if user["last_claim"]:
        unlock = datetime.fromisoformat(user["last_claim"]) + timedelta(hours=1)
        if unlock > datetime.utcnow():
            wait = str(unlock - datetime.utcnow()).split(".")[0]

    body = f"""
    <div class='card'>
      <h2>TON Faucet</h2>
      <p>Базовая награда: {CONFIG['faucet_reward']} TON каждый час.</p>
      <p>Текущий буст дохода: x{income_boost(user):.2f} (чем больше ставишь в казино, тем выше).</p>
      <p>Статус: {wait}</p>
      <form method='post'><button>Собрать TON</button></form>
    </div>
    """
    conn.close()
    return render(body, message)


@app.route("/casino", methods=["GET", "POST"])
def casino():
    if not login_required():
        return redirect(url_for("dashboard"))
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE wallet = ?", (session["wallet"],)).fetchone()
    message = ""

    if request.method == "POST":
        game = request.form.get("game")
        amount = float(request.form.get("amount", 0))
        if game not in GAMES:
            message = "Неизвестная игра"
        elif amount < CONFIG["min_bet"] or amount > CONFIG["max_bet"]:
            message = f"Ставка от {CONFIG['min_bet']} до {CONFIG['max_bet']} TON"
        elif user["balance"] < amount:
            message = "Недостаточно TON"
        else:
            cfg = GAMES[game]
            win = random.random() < cfg["win_chance"]
            profit = amount * (cfg["multiplier"] - 1) if win else -amount
            conn.execute(
                "UPDATE users SET balance = balance + ?, total_bets = total_bets + ?, total_wins = total_wins + ? WHERE id = ?",
                (profit, amount, max(profit, 0), user["id"]),
            )
            conn.execute(
                "INSERT INTO transactions (user_id, kind, amount, note, created_at) VALUES (?, 'casino', ?, ?, ?)",
                (user["id"], profit, f"{cfg['name']} bet {amount}", now_iso()),
            )
            if user["referred_by"]:
                ref_reward = amount * CONFIG["ref_percent"]
                conn.execute(
                    "UPDATE users SET balance = balance + ?, referral_earnings = referral_earnings + ? WHERE id = ?",
                    (ref_reward, ref_reward, user["referred_by"]),
                )
            conn.commit()
            message = f"{'Победа' if win else 'Проигрыш'}: {profit:+.6f} TON"
            user = conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()

    options = "".join(f"<option value='{k}'>{v['name']}</option>" for k, v in GAMES.items())
    games_list = "".join(f"<li>{v['name']} — x{v['multiplier']}</li>" for v in GAMES.values())
    body = f"""
    <div class='card'>
      <h2>Казино (7 игр)</h2>
      <p>Текущий баланс: {user['balance']:.6f} TON</p>
      <p>Общий объём ставок: {user['total_bets']:.4f} TON → Буст дохода x{income_boost(user):.2f}</p>
      <form method='post'>
        <select name='game'>{options}</select>
        <input name='amount' type='number' min='{CONFIG['min_bet']}' step='0.01' placeholder='Ставка TON' required>
        <button>Играть</button>
      </form>
      <ul>{games_list}</ul>
    </div>
    """
    conn.close()
    return render(body, message)


@app.route("/mining", methods=["GET", "POST"])
def mining():
    if not login_required():
        return redirect(url_for("dashboard"))
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE wallet = ?", (session["wallet"],)).fetchone()
    message = ""

    if request.method == "POST":
        action = request.form.get("action")
        if action == "buy":
            th = float(request.form.get("th", 0))
            cost = th * CONFIG["mining_price_per_th"]
            if th <= 0:
                message = "Укажи корректный объём TH/s"
            elif user["balance"] < cost:
                message = "Недостаточно TON для покупки мощности"
            else:
                conn.execute(
                    "UPDATE users SET balance = balance - ?, mining_th = mining_th + ? WHERE id = ?",
                    (cost, th, user["id"]),
                )
                conn.commit()
                message = f"Куплено {th:.2f} TH/s за {cost:.4f} TON"
        if action == "claim":
            last = datetime.fromisoformat(user["last_mining_claim"] or now_iso())
            elapsed_days = max((datetime.utcnow() - last).total_seconds() / 86400, 0)
            daily_income = user["mining_th"] * CONFIG["mining_price_per_th"] / CONFIG["mining_roi_days"]
            reward = daily_income * elapsed_days
            if reward <= 0:
                message = "Пока нечего забирать"
            else:
                conn.execute(
                    "UPDATE users SET balance = balance + ?, last_mining_claim = ? WHERE id = ?",
                    (reward, now_iso(), user["id"]),
                )
                conn.commit()
                message = f"Начислено с майнинга {reward:.6f} TON"
        user = conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()

    daily_income = user["mining_th"] * CONFIG["mining_price_per_th"] / CONFIG["mining_roi_days"]
    body = f"""
    <div class='card'>
      <h2>TON Mining</h2>
      <p>Окупаемость настроена на {CONFIG['mining_roi_days']} дней.</p>
      <p>Мощность: {user['mining_th']:.2f} TH/s</p>
      <p>Доход в день: {daily_income:.6f} TON</p>
      <form method='post'>
        <input type='hidden' name='action' value='buy'>
        <input type='number' name='th' min='0.1' step='0.1' placeholder='Купить TH/s'>
        <button>Купить мощность</button>
      </form>
      <form method='post' style='margin-top:10px;'>
        <input type='hidden' name='action' value='claim'>
        <button>Забрать доход майнинга</button>
      </form>
    </div>
    """
    conn.close()
    return render(body, message)


@app.route("/referrals")
def referrals():
    if not login_required():
        return redirect(url_for("dashboard"))
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE wallet = ?", (session["wallet"],)).fetchone()
    refs = conn.execute("SELECT COUNT(*) cnt FROM users WHERE referred_by = ?", (user["id"],)).fetchone()["cnt"]
    ref_link = request.host_url.rstrip("/") + url_for("dashboard") + f"?ref={user['referral_code']}"
    body = f"""
    <div class='card'>
      <h2>Реферальная система</h2>
      <p>Твой код: <b>{user['referral_code']}</b></p>
      <p>Ссылка: <input value='{ref_link}' style='width:100%'></p>
      <p>Прибыль с рефералов: {user['referral_earnings']:.6f} TON</p>
      <p>Приглашено пользователей: {refs}</p>
      <p>Бонус: {int(CONFIG['ref_percent'] * 100)}% от каждой ставки реферала.</p>
    </div>
    """
    conn.close()
    return render(body)


@app.route("/wallet", methods=["GET", "POST"])
def wallet_page():
    if not login_required():
        return redirect(url_for("dashboard"))
    conn = db()
    user = conn.execute("SELECT * FROM users WHERE wallet = ?", (session["wallet"],)).fetchone()
    message = ""

    if request.method == "POST":
        action = request.form.get("action")
        amount = float(request.form.get("amount", 0))
        if action == "deposit":
            if amount < CONFIG["min_deposit"]:
                message = f"Минимум пополнения через FaucetPay: {CONFIG['min_deposit']} TON"
            else:
                conn.execute("UPDATE users SET balance = balance + ? WHERE id = ?", (amount, user["id"]))
                conn.execute(
                    "INSERT INTO transactions (user_id, kind, amount, note, created_at) VALUES (?, 'deposit', ?, ?, ?)",
                    (user["id"], amount, "FaucetPay deposit (demo)", now_iso()),
                )
                conn.commit()
                message = f"Пополнение через FaucetPay успешно: +{amount:.6f} TON"
        if action == "withdraw":
            if amount < CONFIG["min_withdraw"]:
                message = f"Минимум вывода через FaucetPay: {CONFIG['min_withdraw']} TON"
            elif user["balance"] < amount:
                message = "Недостаточно средств"
            else:
                conn.execute("UPDATE users SET balance = balance - ? WHERE id = ?", (amount, user["id"]))
                conn.execute(
                    "INSERT INTO transactions (user_id, kind, amount, note, created_at) VALUES (?, 'withdraw', ?, ?, ?)",
                    (user["id"], -amount, "FaucetPay withdraw (demo)", now_iso()),
                )
                conn.commit()
                message = f"Запрос на вывод через FaucetPay создан: {amount:.6f} TON"
        user = conn.execute("SELECT * FROM users WHERE id = ?", (user["id"],)).fetchone()

    tx = conn.execute(
        "SELECT kind, amount, note, created_at FROM transactions WHERE user_id = ? ORDER BY id DESC LIMIT 15",
        (user["id"],),
    ).fetchall()
    rows = "".join(
        f"<tr><td>{t['kind']}</td><td>{t['amount']:+.6f}</td><td>{t['note']}</td><td>{t['created_at']}</td></tr>" for t in tx
    )
    body = f"""
    <div class='card'>
      <h2>Кошелёк / FaucetPay</h2>
      <p>Баланс: {user['balance']:.6f} TON</p>
      <form method='post'>
        <input type='hidden' name='action' value='deposit'>
        <input name='amount' type='number' min='0.5' step='0.01' placeholder='Сумма пополнения'>
        <button>Пополнить через FaucetPay</button>
      </form>
      <form method='post' style='margin-top:10px;'>
        <input type='hidden' name='action' value='withdraw'>
        <input name='amount' type='number' min='1' step='0.01' placeholder='Сумма вывода'>
        <button>Вывести через FaucetPay</button>
      </form>
    </div>
    <div class='card'>
      <h3>История операций</h3>
      <table><tr><th>Тип</th><th>Сумма</th><th>Описание</th><th>Время</th></tr>{rows}</table>
    </div>
    """
    conn.close()
    return render(body, message)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("dashboard"))


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
