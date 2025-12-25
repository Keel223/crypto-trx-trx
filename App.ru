#!/usr/bin/env python3
"""
FaucetPay Casino PRO - Полная версия
"""

import os
import sqlite3
import random
import time
import hashlib
import json
from datetime import datetime, timedelta
from flask import Flask, request, redirect, session, render_template_string, jsonify

# ============================================
# КОНФИГУРАЦИЯ
# ============================================

CONFIG = {
    "SECRET_KEY": os.environ.get("SECRET_KEY", "casino-pro-secret-2024"),
    "FAUCETPAY_API_KEY": os.environ.get("868c8c9b389194b370dcf51ab87e0447e50e11a8b25abf46136035e07788b5ae", ""),
    
    "FAUCET": {
        "reward_base": 0.0001,
        "timer_minutes": 5,
        "currency": "TRX",
        "min_withdraw": 0.5,
        "fee": 2.0,
    },
    
    "GAMES": {
        "min_bet": 0.00001,
        "max_bet": 1.0,
        "coin_flip": {"multiplier": 1.95},
        "dice": {"multiplier": 5.8},
    },
    
    "VIP": {
        "levels": {
            1: {"name": "Bronze", "multiplier": 1.0, "color": "#CD7F32"},
            2: {"name": "Silver", "multiplier": 1.5, "color": "#C0C0C0"},
            3: {"name": "Gold", "multiplier": 2.0, "color": "#FFD700"},
        }
    },
    
    "ADS": {
        "enabled": True,
        "click_bonus": 0.00005,
    }
}

# ============================================
# ИНИЦИАЛИЗАЦИЯ FLASK
# ============================================

app = Flask(__name__)
app.secret_key = CONFIG["SECRET_KEY"]

# База данных в памяти
DB = sqlite3.connect(':memory:', check_same_thread=False)
c = DB.cursor()

# ============================================
# БАЗА ДАННЫХ
# ============================================

def init_db():
    c.execute('''CREATE TABLE IF NOT EXISTS users
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  wallet TEXT UNIQUE,
                  balance REAL DEFAULT 0.001,
                  total_claimed REAL DEFAULT 0.0,
                  total_bets REAL DEFAULT 0.0,
                  total_wins REAL DEFAULT 0.0,
                  claim_count INTEGER DEFAULT 0,
                  claim_streak INTEGER DEFAULT 0,
                  last_claim TIMESTAMP,
                  vip_level INTEGER DEFAULT 1,
                  reg_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    
    c.execute('''CREATE TABLE IF NOT EXISTS transactions
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id INTEGER,
                  type TEXT,
                  amount REAL,
                  status TEXT,
                  description TEXT,
                  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    
    DB.commit()

init_db()

# ============================================
# HTML ШАБЛОНЫ
# ============================================

MAIN_TEMPLATE = '''
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🎰 FaucetPay Casino PRO</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        :root {
            --primary: #667eea;
            --secondary: #764ba2;
            --success: #28a745;
            --warning: #ffc107;
        }
        
        body {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            min-height: 100vh;
            color: #333;
            font-family: 'Segoe UI', sans-serif;
        }
        
        .glass-card {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 25px;
            box-shadow: 0 15px 35px rgba(0,0,0,0.2);
            border: 1px solid rgba(255,255,255,0.1);
            margin-bottom: 25px;
        }
        
        .btn-gradient {
            background: linear-gradient(45deg, var(--primary), var(--secondary));
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 50px;
            font-weight: 600;
            transition: all 0.3s;
        }
        
        .btn-gradient:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.2);
        }
        
        .balance-display {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(45deg, var(--success), #20c997);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            text-align: center;
            margin: 20px 0;
        }
        
        .game-card {
            background: white;
            border-radius: 15px;
            padding: 20px;
            margin: 10px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
            border: 2px solid transparent;
        }
        
        .game-card:hover {
            border-color: var(--primary);
            transform: scale(1.05);
        }
        
        .vip-badge {
            background: linear-gradient(45deg, #FFD700, #FFA500);
            color: #000;
            padding: 5px 15px;
            border-radius: 20px;
            font-weight: bold;
            display: inline-block;
        }
        
        .stat-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            margin: 5px;
        }
        
        .stat-value {
            font-size: 1.8rem;
            font-weight: bold;
            color: var(--primary);
        }
        
        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.05); }
            100% { transform: scale(1); }
        }
        
        .pulse {
            animation: pulse 2s infinite;
        }
        
        .nav-tabs .nav-link.active {
            background: linear-gradient(45deg, var(--primary), var(--secondary));
            color: white !important;
            border-radius: 10px;
        }
        
        .ad-container {
            border: 3px dashed var(--success);
            border-radius: 15px;
            padding: 20px;
            margin: 20px 0;
            background: white;
        }
    </style>
</head>
<body>
    <!-- Навигация -->
    <nav class="navbar navbar-expand-lg navbar-dark" style="background: rgba(0,0,0,0.8);">
        <div class="container">
            <a class="navbar-brand" href="/">
                <i class="fas fa-gem"></i>
                <span style="font-weight: 800; margin-left: 10px;">FAUCETPAY CASINO PRO</span>
            </a>
            {% if session.wallet %}
            <div class="navbar-text text-white">
                <i class="fas fa-wallet"></i> {{ session.wallet[:8] }}...{{ session.wallet[-4:] }}
            </div>
            {% endif %}
        </div>
    </nav>
    
    <div class="container mt-4">
        {% with messages = get_flashed_messages() %}
            {% if messages %}
                {% for message in messages %}
                <div class="alert alert-info alert-dismissible fade show">
                    {{ message }}
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
                {% endfor %}
            {% endif %}
        {% endwith %}
        
        {% block content %}{% endblock %}
        
        <footer class="text-center text-white mt-5 p-4">
            <p>FaucetPay Casino © 2024 | Только для развлекательных целей</p>
        </footer>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Автоматическое скрытие сообщений
        setTimeout(() => {
            document.querySelectorAll('.alert').forEach(alert => {
                alert.style.transition = 'opacity 0.5s';
                alert.style.opacity = '0';
                setTimeout(() => alert.remove(), 500);
            });
        }, 5000);
        
        // Игры
        function playGame(gameType) {
            let amount = prompt('Введите ставку в TRX:', '0.00001');
            if (amount && !isNaN(amount) && parseFloat(amount) > 0) {
                window.location.href = '/play/' + gameType + '?amount=' + amount;
            } else {
                alert('Некорректная сумма!');
            }
        }
        
        // Копирование реферальной ссылки
        function copyRefLink() {
            let link = document.getElementById('refLink');
            link.select();
            link.setSelectionRange(0, 99999);
            navigator.clipboard.writeText(link.value);
            alert('Ссылка скопирована!');
        }
        
        // Клик по рекламе
        function clickAd() {
            fetch('/ad_click')
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        alert('+ ' + data.bonus + ' TRX за клик!');
                        location.reload();
                    }
                });
        }
    </script>
</body>
</html>
'''

LOGIN_TEMPLATE = '''
{% extends "base.html" %}
{% block content %}
<div class="row">
    <div class="col-md-6 offset-md-3">
        <div class="glass-card text-center">
            <h1 class="display-4 mb-4">🎰 Добро пожаловать!</h1>
            <p class="lead mb-4">Получайте TRX бесплатно и играйте в казино</p>
            
            <form method="POST" action="/login">
                <div class="input-group input-group-lg mb-3">
                    <span class="input-group-text"><i class="fas fa-wallet"></i></span>
                    <input type="text" class="form-control" name="wallet" 
                           placeholder="Введите ваш FaucetPay кошелёк" required>
                </div>
                <button class="btn btn-gradient btn-lg w-100 pulse" type="submit">
                    <i class="fas fa-play-circle"></i> НАЧАТЬ ИГРАТЬ
                </button>
            </form>
            
            <div class="mt-5">
                <h5><i class="fas fa-gift"></i> Стартовый бонус: 0.001 TRX</h5>
                <h5><i class="fas fa-coins"></i> Кран: каждые 5 минут</h5>
                <h5><i class="fas fa-gamepad"></i> 6+ игр казино</h5>
            </div>
        </div>
    </div>
</div>
{% endblock %}
'''

DASHBOARD_TEMPLATE = '''
{% extends "base.html" %}
{% block content %}
<div class="row">
    <!-- Левая колонка -->
    <div class="col-md-4">
        <div class="glass-card">
            <div class="text-center">
                <div class="vip-badge mb-3">
                    <i class="fas fa-crown"></i> {{ vip_info.name }}
                </div>
                <div class="balance-display">{{ "%.6f"|format(user.balance) }} TRX</div>
                
                <div class="row mt-4">
                    <div class="col-6">
                        <div class="stat-item">
                            <div class="stat-value">{{ user.level }}</div>
                            <div class="stat-label">Уровень</div>
                        </div>
                    </div>
                    <div class="col-6">
                        <div class="stat-item">
                            <div class="stat-value">{{ user.claim_streak }}</div>
                            <div class="stat-label">Стрик</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="glass-card">
            <h4><i class="fas fa-faucet"></i> Кран TRX</h4>
            {% if can_claim %}
            <form action="/claim" method="POST">
                <button class="btn btn-gradient w-100 pulse" type="submit">
                    <i class="fas fa-coins"></i> ПОЛУЧИТЬ {{ reward|round(6) }} TRX
                </button>
            </form>
            {% else %}
            <button class="btn btn-secondary w-100" disabled>
                <i class="fas fa-clock"></i> ЖДИТЕ {{ wait_time }} МИН
            </button>
            <div class="progress mt-3" style="height: 10px;">
                <div class="progress-bar bg-success" 
                     style="width: {{ progress }}%"></div>
            </div>
            {% endif %}
        </div>
        
        <!-- Быстрые действия -->
        <div class="glass-card">
            <h5><i class="fas fa-bolt"></i> Быстрые действия</h5>
            <div class="d-grid gap-2">
                <button class="btn btn-outline-primary" onclick="playGame('coin_flip')">
                    <i class="fas fa-coins"></i> Быстрая игра
                </button>
                <button class="btn btn-outline-success" onclick="document.getElementById('depositModal').style.display='block'">
                    <i class="fas fa-plus-circle"></i> Пополнить
                </button>
                <button class="btn btn-outline-warning" onclick="document.getElementById('withdrawModal').style.display='block'">
                    <i class="fas fa-money-bill-wave"></i> Вывести
                </button>
            </div>
        </div>
    </div>
    
    <!-- Центральная колонка: Игры -->
    <div class="col-md-5">
        <div class="glass-card">
            <h4><i class="fas fa-gamepad"></i> Игры казино</h4>
            
            <div class="row">
                {% for game in games %}
                <div class="col-6 col-md-4 mb-3">
                    <div class="game-card" onclick="playGame('{{ game.id }}')">
                        <div class="game-icon" style="font-size: 2.5rem;">{{ game.icon }}</div>
                        <h6>{{ game.name }}</h6>
                        <small class="text-success">{{ game.multiplier }}</small>
                    </div>
                </div>
                {% endfor %}
            </div>
        </div>
        
        <!-- Реклама -->
        <div class="ad-container">
            <h5><i class="fas fa-ad"></i> Поддержите проект</h5>
            <p class="text-muted">Кликайте по рекламе для поддержки</p>
            <div style="background: #f8f9fa; padding: 20px; border-radius: 10px; text-align: center;">
                <p><strong>Рекламный блок</strong></p>
                <p>Здесь будет реклама A-ADS</p>
            </div>
            <button class="btn btn-success mt-3 w-100" onclick="clickAd()">
                <i class="fas fa-mouse-pointer"></i> Кликнуть (+{{ CONFIG.ADS.click_bonus }} TRX)
            </button>
        </div>
    </div>
    
    <!-- Правая колонка: Статистика -->
    <div class="col-md-3">
        <div class="glass-card">
            <h4><i class="fas fa-chart-bar"></i> Статистика</h4>
            <div class="stat-item mb-2">
                <div class="stat-value">{{ user.claim_count }}</div>
                <div class="stat-label">Клеймов</div>
            </div>
            <div class="stat-item mb-2">
                <div class="stat-value">{{ "%.3f"|format(user.total_bets) }}</div>
                <div class="stat-label">Ставок (TRX)</div>
            </div>
            <div class="stat-item mb-2">
                <div class="stat-value">{{ "%.3f"|format(user.total_wins) }}</div>
                <div class="stat-label">Выиграно</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{{ user.vip_level }}</div>
                <div class="stat-label">VIP уровень</div>
            </div>
        </div>
        
        <div class="glass-card">
            <h5><i class="fas fa-users"></i> Рефералы</h5>
            <div class="input-group mb-3">
                <input type="text" class="form-control" id="refLink" 
                       value="{{ request.host_url }}?ref={{ user.ref_code }}" readonly>
                <button class="btn btn-outline-secondary" onclick="copyRefLink()">
                    <i class="fas fa-copy"></i>
                </button>
            </div>
        </div>
        
        <div class="glass-card">
            <h5><i class="fas fa-user-shield"></i> Админка</h5>
            <a href="/admin" class="btn btn-outline-dark w-100">
                <i class="fas fa-cog"></i> Панель управления
            </a>
        </div>
    </div>
</div>

<!-- Модальные окна -->
<div id="withdrawModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); z-index:1000;">
    <div style="background:white; margin:100px auto; padding:20px; border-radius:10px; max-width:500px;">
        <h5><i class="fas fa-money-bill-wave"></i> Вывод средств</h5>
        <form action="/withdraw" method="POST">
            <input type="number" name="amount" class="form-control mb-2" placeholder="Сумма TRX" step="0.000001">
            <button type="submit" class="btn btn-warning">Вывести</button>
            <button type="button" class="btn btn-secondary" onclick="this.parentElement.parentElement.style.display='none'">Отмена</button>
        </form>
    </div>
</div>

<div id="depositModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); z-index:1000;">
    <div style="background:white; margin:100px auto; padding:20px; border-radius:10px; max-width:500px;">
        <h5><i class="fas fa-plus-circle"></i> Пополнение баланса</h5>
        <form action="/deposit" method="POST">
            <input type="number" name="amount" class="form-control mb-2" placeholder="Сумма TRX" step="0.000001">
            <button type="submit" class="btn btn-success">Пополнить</button>
            <button type="button" class="btn btn-secondary" onclick="this.parentElement.parentElement.style.display='none'">Отмена</button>
        </form>
    </div>
</div>
{% endblock %}
'''

# ============================================
# ФУНКЦИИ
# ============================================

def get_user(wallet):
    c = DB.cursor()
    c.execute("SELECT * FROM users WHERE wallet = ?", (wallet,))
    row = c.fetchone()
    
    if row:
        return {
            'id': row[0],
            'wallet': row[1],
            'balance': row[2] or 0.001,
            'total_claimed': row[3] or 0,
            'total_bets': row[4] or 0,
            'total_wins': row[5] or 0,
            'claim_count': row[6] or 0,
            'claim_streak': row[7] or 0,
            'last_claim': row[8],
            'vip_level': row[9] or 1,
            'reg_date': row[10],
            'level': 1,
            'ref_code': hashlib.md5(wallet.encode()).hexdigest()[:8].upper()
        }
    return None

def create_user(wallet):
    c = DB.cursor()
    try:
        ref_code = hashlib.md5(f"{wallet}{time.time()}".encode()).hexdigest()[:8].upper()
        c.execute('''INSERT INTO users (wallet, balance, ref_code) VALUES (?, ?, ?)''',
                 (wallet, 0.001, ref_code))
        DB.commit()
        return True
    except:
        return False

# ============================================
# РОУТЫ
# ============================================

@app.route('/')
def index():
    wallet = session.get('wallet')
    
    if not wallet:
        return render_template_string(MAIN_TEMPLATE + LOGIN_TEMPLATE)
    
    user = get_user(wallet)
    if not user:
        create_user(wallet)
        user = get_user(wallet)
    
    # Проверка клейма
    can_claim = True
    wait_time = 0
    progress = 100
    reward = CONFIG["FAUCET"]["reward_base"] * CONFIG["VIP"]["levels"][user['vip_level']]["multiplier"]
    
    if user['last_claim']:
        try:
            last_claim = datetime.strptime(user['last_claim'], '%Y-%m-%d %H:%M:%S.%f')
        except:
            last_claim = datetime.now() - timedelta(hours=1)
        
        next_claim = last_claim + timedelta(minutes=CONFIG["FAUCET"]["timer_minutes"])
        if datetime.now() < next_claim:
            can_claim = False
            wait_time = (next_claim - datetime.now()).seconds // 60
            total_seconds = CONFIG["FAUCET"]["timer_minutes"] * 60
            passed_seconds = (datetime.now() - last_claim).seconds
            progress = min(100, (passed_seconds / total_seconds) * 100)
    
    vip_info = CONFIG["VIP"]["levels"][user['vip_level']]
    
    games = [
        {"id": "coin_flip", "name": "Орёл/Решка", "icon": "🪙", "multiplier": "x1.95"},
        {"id": "dice", "name": "Кости", "icon": "🎲", "multiplier": "x5.8"},
        {"id": "slots", "name": "Слоты", "icon": "🎰", "multiplier": "до x100"},
        {"id": "blackjack", "name": "Блэкджек", "icon": "♠️", "multiplier": "x2.0"},
        {"id": "roulette", "name": "Рулетка", "icon": "🎡", "multiplier": "x36"},
        {"id": "crash", "name": "Краш", "icon": "🚀", "multiplier": "до x100"},
    ]
    
    template = MAIN_TEMPLATE + DASHBOARD_TEMPLATE
    return render_template_string(template, 
                                 user=user,
                                 vip_info=vip_info,
                                 can_claim=can_claim,
                                 wait_time=wait_time,
                                 progress=progress,
                                 reward=reward,
                                 games=games,
                                 CONFIG=CONFIG)

@app.route('/login', methods=['POST'])
def login():
    wallet = request.form.get('wallet', '').strip()
    
    if not wallet or len(wallet) < 3:
        session['error'] = 'Введите кошелёк'
        return redirect('/')
    
    session['wallet'] = wallet
    return redirect('/')

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/')

@app.route('/claim', methods=['POST'])
def claim():
    wallet = session.get('wallet')
    if not wallet:
        return redirect('/')
    
    user = get_user(wallet)
    if not user:
        return redirect('/')
    
    # Проверка времени
    if user['last_claim']:
        try:
            last_claim = datetime.strptime(user['last_claim'], '%Y-%m-%d %H:%M:%S.%f')
        except:
            last_claim = datetime.now() - timedelta(hours=1)
        
        next_claim = last_claim + timedelta(minutes=CONFIG["FAUCET"]["timer_minutes"])
        if datetime.now() < next_claim:
            session['error'] = f'Ждите {(next_claim - datetime.now()).seconds // 60} минут'
            return redirect('/')
    
    # Начисление
    reward = CONFIG["FAUCET"]["reward_base"] * CONFIG["VIP"]["levels"][user['vip_level']]["multiplier"]
    
    c = DB.cursor()
    new_streak = user['claim_streak'] + 1 if user['last_claim'] else 1
    
    c.execute('''UPDATE users SET 
                balance = balance + ?,
                total_claimed = total_claimed + ?,
                claim_count = claim_count + 1,
                claim_streak = ?,
                last_claim = ?
                WHERE wallet = ?''',
             (reward, reward, new_streak, datetime.now(), wallet))
    
    DB.commit()
    
    session['success'] = f'Получено {reward:.6f} TRX! Стрик: {new_streak}'
    return redirect('/')

@app.route('/play/<game>')
def play_game(game):
    wallet = session.get('wallet')
    if not wallet:
        return redirect('/')
    
    try:
        amount = float(request.args.get('amount', 0.00001))
    except:
        session['error'] = 'Неверная сумма'
        return redirect('/')
    
    if amount < CONFIG["GAMES"]["min_bet"] or amount > CONFIG["GAMES"]["max_bet"]:
        session['error'] = f'Ставка от {CONFIG["GAMES"]["min_bet"]} до {CONFIG["GAMES"]["max_bet"]} TRX'
        return redirect('/')
    
    user = get_user(wallet)
    if not user or user['balance'] < amount:
        session['error'] = 'Недостаточно средств'
        return redirect('/')
    
    # Логика игры
    win = random.random() < 0.495  # 49.5% шанс
    
    if game == 'coin_flip':
        multiplier = CONFIG["GAMES"]["coin_flip"]["multiplier"]
    elif game == 'dice':
        multiplier = CONFIG["GAMES"]["dice"]["multiplier"]
    elif game == 'slots':
        multiplier = random.choice([0, 2, 5, 10, 20, 50, 100])
        win = multiplier > 0
    else:
        multiplier = 2.0
    
    profit = (amount * multiplier) - amount if win else -amount
    
    c = DB.cursor()
    c.execute('''UPDATE users SET 
                balance = balance + ?,
                total_bets = total_bets + ?,
                total_wins = total_wins + ?
                WHERE wallet = ?''',
             (profit, amount, max(profit, 0), wallet))
    
    DB.commit()
    
    if profit > 0:
        session['success'] = f'🎉 Выигрыш {profit:.6f} TRX (x{multiplier})!'
    else:
        session['error'] = f'💸 Проигрыш {abs(profit):.6f} TRX'
    
    return redirect('/')

@app.route('/withdraw', methods=['POST'])
def withdraw():
    wallet = session.get('wallet')
    if not wallet:
        return redirect('/')
    
    try:
        amount = float(request.form.get('amount', 0))
    except:
        session['error'] = 'Неверная сумма'
        return redirect('/')
    
    if amount < CONFIG["FAUCET"]["min_withdraw"]:
        session['error'] = f'Минимум {CONFIG["FAUCET"]["min_withdraw"]} TRX'
        return redirect('/')
    
    user = get_user(wallet)
    if not user or user['balance'] < amount:
        session['error'] = 'Недостаточно средств'
        return redirect('/')
    
    # Тестовый вывод
    fee = amount * (CONFIG["FAUCET"]["fee"] / 100)
    net_amount = amount - fee
    
    c = DB.cursor()
    c.execute('UPDATE users SET balance = balance - ? WHERE wallet = ?', (amount, wallet))
    DB.commit()
    
    session['success'] = f'✅ Вывод {net_amount:.6f} TRX обработан (тестовый режим)'
    return redirect('/')

@app.route('/deposit', methods=['POST'])
def deposit():
    wallet = session.get('wallet')
    if not wallet:
        return redirect('/')
    
    try:
        amount = float(request.form.get('amount', 0))
    except:
        session['error'] = 'Неверная сумма'
        return redirect('/')
    
    if amount < 0.1:
        session['error'] = 'Минимум 0.1 TRX'
        return redirect('/')
    
    c = DB.cursor()
    c.execute('UPDATE users SET balance = balance + ? WHERE wallet = ?', (amount, wallet))
    DB.commit()
    
    # Обновление VIP при больших депозитах
    if amount >= 10:
        c.execute('UPDATE users SET vip_level = 2 WHERE wallet = ?', (wallet,))
    if amount >= 50:
        c.execute('UPDATE users SET vip_level = 3 WHERE wallet = ?', (wallet,))
    
    session['success'] = f'✅ Баланс пополнен на {amount:.6f} TRX!'
    return redirect('/')

@app.route('/ad_click')
def ad_click():
    wallet = session.get('wallet')
    if not wallet:
        return jsonify({'success': False})
    
    bonus = CONFIG["ADS"]["click_bonus"]
    
    c = DB.cursor()
    c.execute('UPDATE users SET balance = balance + ? WHERE wallet = ?', (bonus, wallet))
    DB.commit()
    
    return jsonify({
        'success': True,
        'bonus': bonus
    })

@app.route('/admin')
def admin():
    # Простая админка
    c = DB.cursor()
    c.execute('SELECT COUNT(*) FROM users')
    user_count = c.fetchone()[0]
    
    c.execute('SELECT SUM(balance) FROM users')
    total_balance = c.fetchone()[0] or 0
    
    return f'''
    <h1>Админ-панель</h1>
    <p>Пользователей: {user_count}</p>
    <p>Общий баланс: {total_balance:.6f} TRX</p>
    <a href="/">На главную</a>
    '''

# ============================================
# ЗАПУСК
# ============================================

if __name__ == '__main__':
    app.run(debug=True)
