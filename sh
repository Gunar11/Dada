import logging
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes
import sqlite3
from datetime import datetime

# Настройка логирования
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Вопросы и ответы
QUESTIONS = [
    {
        'question': '1. Кто помогал клубочку прятаться от Бабы-яги в сказке "Гуси-лебеди"?',
        'options': ['Яблоня', 'Речка', 'Печка', 'Мышка'],
        'correct': 2,  # Печка
        'points': 10
    },
    {
        'question': '2. Какое волшебное слово говорил Емеля, чтобы щука выполняла его желания?',
        'options': ['По щучьему велению', 'Сим-сим откройся', 'Крекс-фекс-пекс', 'Раз-два-три'],
        'correct': 0,  # По щучьему велению
        'points': 10
    },
    {
        'question': '3. Кого сначала испугался Колобок?',
        'options': ['Медведя', 'Зайца', 'Волка', 'Лису'],
        'correct': 1,  # Зайца
        'points': 10
    },
    {
        'question': '4. Из какого предмета сделана Кащею Бессмертному смерть?',
        'options': ['Из камня', 'Из яйца', 'Из иглы', 'Из зеркала'],
        'correct': 2,  # Из иглы
        'points': 15
    },
    {
        'question': '5. Сколько раз богатыри бились с Чудом-Юдом в сказке "Иван-крестьянский сын и чудо-юдо"?',
        'options': ['Один раз', 'Два раза', 'Три раза', 'Четыре раза'],
        'correct': 2,  # Три раза
        'points': 15
    },
    {
        'question': '6. Что попросила у старика золотая рыбка за свое спасение?',
        'options': ['Новый дом', 'Свободу', 'Ничего', 'Коронацию'],
        'correct': 2,  # Ничего
        'points': 10
    },
    {
        'question': '7. Какое прозвище было у Ивана - младшего сына в сказке "Конек-Горбунок"?',
        'options': ['Дурак', 'Умник', 'Богатырь', 'Силач'],
        'correct': 0,  # Дурак
        'points': 10
    },
    {
        'question': '8. Кто помог Финисту - Ясному Соколу вернуть свой облик?',
        'options': ['Баба-яга', 'Василиса Премудрая', 'Марья-искусница', 'Царевна-лягушка'],
        'correct': 2,  # Марья-искусница
        'points': 20
    }
]

# База данных
def init_db():
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    
    # Таблица для хранения результатов пользователей
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            user_id INTEGER PRIMARY KEY,
            username TEXT,
            first_name TEXT,
            last_name TEXT,
            total_score INTEGER DEFAULT 0,
            last_played TIMESTAMP
        )
    ''')
    
    # Таблица для хранения ответов на вопросы
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS user_answers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            question_number INTEGER,
            score INTEGER,
            answered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users (user_id)
        )
    ''')
    
    conn.commit()
    conn.close()

# Функции для работы с базой данных
def get_or_create_user(user_id, username, first_name, last_name):
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT OR IGNORE INTO users (user_id, username, first_name, last_name) 
        VALUES (?, ?, ?, ?)
    ''', (user_id, username, first_name, last_name))
    
    cursor.execute('SELECT * FROM users WHERE user_id = ?', (user_id,))
    user = cursor.fetchone()
    
    conn.commit()
    conn.close()
    return user

def save_answer(user_id, question_num, score):
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    
    # Удаляем предыдущий ответ на этот вопрос, если он был
    cursor.execute('''
        DELETE FROM user_answers 
        WHERE user_id = ? AND question_number = ?
    ''', (user_id, question_num))
    
    # Сохраняем новый ответ
    cursor.execute('''
        INSERT INTO user_answers (user_id, question_number, score)
        VALUES (?, ?, ?)
    ''', (user_id, question_num, score))
    
    # Обновляем общий счет пользователя
    cursor.execute('''
        UPDATE users 
        SET total_score = (
            SELECT COALESCE(SUM(score), 0) 
            FROM user_answers 
            WHERE user_id = ?
        ),
        last_played = CURRENT_TIMESTAMP
        WHERE user_id = ?
    ''', (user_id, user_id))
    
    conn.commit()
    conn.close()

def get_user_score(user_id):
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    
    cursor.execute('SELECT total_score FROM users WHERE user_id = ?', (user_id,))
    result = cursor.fetchone()
    
    conn.close()
    return result[0] if result else 0

def get_leaderboard():
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT user_id, username, first_name, last_name, total_score
        FROM users 
        WHERE total_score > 0
        ORDER BY total_score DESC, last_played ASC
        LIMIT 10
    ''')
    
    leaders = cursor.fetchall()
    conn.close()
    return leaders

# Команда /start
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    get_or_create_user(user.id, user.username, user.first_name, user.last_name)
    
    welcome_text = f"""
👋 Привет, {user.first_name}!

📚 Добро пожаловать в викторину по русским народным сказкам!

📝 В викторине {len(QUESTIONS)} вопросов разной сложности.
🏆 За каждый правильный ответ ты получаешь очки (10-20 за вопрос).

🎮 Начнем викторину?

Доступные команды:
/start - начать/перезапустить викторину
/quiz - начать викторину
/score - посмотреть свой счет
/leaderboard - посмотреть таблицу лидеров
/rules - правила викторины
    """
    
    keyboard = [
        [InlineKeyboardButton("🎮 Начать викторину", callback_data='start_quiz')],
        [InlineKeyboardButton("📊 Таблица лидеров", callback_data='show_leaderboard')],
        [InlineKeyboardButton("📋 Правила", callback_data='show_rules')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(welcome_text, reply_markup=reply_markup)

# Команда /rules
async def rules(update: Update, context: ContextTypes.DEFAULT_TYPE):
    rules_text = """
📋 **Правила викторины:**

1. Всего в викторине 8 вопросов
2. Каждый вопрос имеет 4 варианта ответа
3. За правильный ответ начисляются очки:
   • Легкие вопросы: 10 очков
   • Средние вопросы: 15 очков
   • Сложные вопросы: 20 очков
4. Можно отвечать на вопросы в любом порядке
5. Победителем становится участник с наибольшим количеством очков
6. В таблице лидеров отображаются первые три места

🏆 **Система начисления очков:**
• 1 место: 🥇 Золото
• 2 место: 🥈 Серебро  
• 3 место: 🥉 Бронза

Удачи! 🍀
    """
    
    keyboard = [[InlineKeyboardButton("🎮 Начать викторину", callback_data='start_quiz')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(rules_text, reply_markup=reply_markup)

# Команда /quiz
async def quiz(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await show_question(update, context, 0)

# Показать вопрос
async def show_question(update: Update, context: ContextTypes.DEFAULT_TYPE, question_num):
    question_data = QUESTIONS[question_num]
    
    # Создаем кнопки с вариантами ответов
    keyboard = []
    for i, option in enumerate(question_data['options']):
        keyboard.append([InlineKeyboardButton(
            f"{chr(65+i)}) {option}", 
            callback_data=f"answer_{question_num}_{i}"
        )])
    
    # Добавляем кнопки навигации
    nav_buttons = []
    if question_num > 0:
        nav_buttons.append(InlineKeyboardButton("◀️ Назад", callback_data=f"nav_{question_num-1}"))
    
    if question_num < len(QUESTIONS) - 1:
        nav_buttons.append(InlineKeyboardButton("Далее ▶️", callback_data=f"nav_{question_num+1}"))
    
    if nav_buttons:
        keyboard.append(nav_buttons)
    
    keyboard.append([
        InlineKeyboardButton("📊 Результаты", callback_data="show_results"),
        InlineKeyboardButton("🏆 Лидеры", callback_data="show_leaderboard")
    ])
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    # Формируем текст вопроса
    question_text = f"""
{question_data['question']}

💰 Стоимость вопроса: {question_data['points']} очков

Варианты ответов:
A) {question_data['options'][0]}
B) {question_data['options'][1]}
C) {question_data['options'][2]}
D) {question_data['options'][3]}

Вопрос {question_num + 1} из {len(QUESTIONS)}
    """
    
    if update.callback_query:
        await update.callback_query.edit_message_text(
            text=question_text,
            reply_markup=reply_markup
        )
    else:
        await update.message.reply_text(question_text, reply_markup=reply_markup)

# Обработка ответов
async def handle_answer(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    # Извлекаем данные из callback_data
    data = query.data.split('_')
    question_num = int(data[1])
    selected_option = int(data[2])
    
    question_data = QUESTIONS[question_num]
    user_id = query.from_user.id
    user = get_or_create_user(user_id, query.from_user.username, 
                             query.from_user.first_name, query.from_user.last_name)
    
    # Проверяем ответ
    is_correct = selected_option == question_data['correct']
    score = question_data['points'] if is_correct else 0
    
    # Сохраняем ответ
    save_answer(user_id, question_num, score)
    
    # Показываем результат
    result_text = f"""
{'✅ Правильно!' if is_correct else '❌ Неправильно!'}

{'🎉 Вы заработали ' + str(score) + ' очков!' if is_correct else 'Правильный ответ: ' + question_data['options'][question_data['correct']]}

Ваш текущий счет: {get_user_score(user_id)} очков

Продолжим?
    """
    
    keyboard = [
        [
            InlineKeyboardButton("➡️ Следующий вопрос", callback_data=f"nav_{question_num+1}"),
            InlineKeyboardButton("📊 Результаты", callback_data="show_results")
        ] if question_num < len(QUESTIONS) - 1 else 
        [
            InlineKeyboardButton("📊 Показать результаты", callback_data="show_results")
        ]
    ]
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(text=result_text, reply_markup=reply_markup)

# Показать результаты
async def show_results(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    user_id = query.from_user.id
    score = get_user_score(user_id)
    
    # Получаем все ответы пользователя
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    cursor.execute('''
        SELECT question_number, score 
        FROM user_answers 
        WHERE user_id = ? 
        ORDER BY question_number
    ''', (user_id,))
    answers = cursor.fetchall()
    conn.close()
    
    # Формируем текст с результатами
    result_text = f"""
📊 **Ваши результаты:**

🎯 Общий счет: {score} очков

📝 Ответы на вопросы:
"""
    
    for answer in answers:
        q_num, q_score = answer
        result_text += f"{q_num + 1}. {'✅' if q_score > 0 else '❌'} ({q_score} очков)\n"
    
    result_text += f"""
━━━━━━━━━━━━━━━━━━━━
🎮 Прогресс: {len(answers)}/{len(QUESTIONS)} вопросов
📈 Правильных ответов: {len([a for a in answers if a[1] > 0])}

Что дальше?
    """
    
    keyboard = [
        [InlineKeyboardButton("🎮 Продолжить викторину", callback_data=f"nav_{len(answers)}")],
        [InlineKeyboardButton("🏆 Таблица лидеров", callback_data="show_leaderboard")],
        [InlineKeyboardButton("🔄 Начать заново", callback_data="reset_quiz")]
    ]
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(text=result_text, reply_markup=reply_markup)

# Показать таблицу лидеров
async def show_leaderboard_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await show_leaderboard_internal(update, context)

async def show_leaderboard_internal(update: Update, context: ContextTypes.DEFAULT_TYPE, is_callback=False):
    leaders = get_leaderboard()
    
    if not leaders:
        leaderboard_text = "🏆 Таблица лидеров пуста!\n\nБудьте первым, кто ответит на вопросы викторины!"
    else:
        leaderboard_text = "🏆 **ТОП-10 ЛИДЕРОВ** 🏆\n\n"
        
        # Медали для первых трех мест
        medals = ["🥇", "🥈", "🥉"]
        
        for i, (user_id, username, first_name, last_name, score) in enumerate(leaders):
            medal = medals[i] if i < 3 else f"{i+1}."
            name = f"@{username}" if username else f"{first_name} {last_name or ''}".strip()
            leaderboard_text += f"{medal} {name}: {score} очков\n"
    
    leaderboard_text += "\n━━━━━━━━━━━━━━━━━━━━\n"
    
    keyboard = [
        [InlineKeyboardButton("🎮 Начать викторину", callback_data='start_quiz')],
        [InlineKeyboardButton("📊 Мои результаты", callback_data='show_results')]
    ]
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    if is_callback:
        await update.callback_query.edit_message_text(
            text=leaderboard_text,
            reply_markup=reply_markup
        )
    else:
        await update.message.reply_text(leaderboard_text, reply_markup=reply_markup)

# Команда /score
async def score(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    score = get_user_score(user_id)
    
    score_text = f"""
📊 **Ваш счет: {score} очков**

🎮 Пройдите викторину, чтобы улучшить свой результат!
    """
    
    keyboard = [[InlineKeyboardButton("🎮 Начать викторину", callback_data='start_quiz')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(score_text, reply_markup=reply_markup)

# Обработка навигации
async def handle_navigation(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    data = query.data.split('_')
    question_num = int(data[1])
    
    if 0 <= question_num < len(QUESTIONS):
        await show_question(update, context, question_num)

# Сброс викторины
async def reset_quiz(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    user_id = query.from_user.id
    conn = sqlite3.connect('fairy_tales_quiz.db')
    cursor = conn.cursor()
    
    # Удаляем все ответы пользователя
    cursor.execute('DELETE FROM user_answers WHERE user_id = ?', (user_id,))
    cursor.execute('UPDATE users SET total_score = 0 WHERE user_id = ?', (user_id,))
    
    conn.commit()
    conn.close()
    
    await show_question(update, context, 0)

# Обработка callback запросов
async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    data = query.data
    
    if data == 'start_quiz':
        await query.answer()
        await show_question(update, context, 0)
    elif data.startswith('answer_'):
        await handle_answer(update, context)
    elif data.startswith('nav_'):
        await handle_navigation(update, context)
    elif data == 'show_results':
        await show_results(update, context)
    elif data == 'show_leaderboard':
        await query.answer()
        await show_leaderboard_internal(update, context, is_callback=True)
    elif data == 'show_rules':
        await query.answer()
        await rules_callback(update, context)
    elif data == 'reset_quiz':
        await reset_quiz(update, context)

async def rules_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    rules_text = """
📋 **Правила викторины:**

1. Всего в викторине 8 вопросов
2. Каждый вопрос имеет 4 варианта ответа
3. За правильный ответ начисляются очки:
   • Легкие вопросы: 10 очков
   • Средние вопросы: 15 очков
   • Сложные вопросы: 20 очков
4. Можно отвечать на вопросы в любом порядке
5. Победителем становится участник с наибольшим количеством очков
6. В таблице лидеров отображаются первые три места

🏆 **Система начисления очков:**
• 1 место: 🥇 Золото
• 2 место: 🥈 Серебро  
• 3 место: 🥉 Бронза

Удачи! 🍀
    """
    
    keyboard = [[InlineKeyboardButton("🎮 Начать викторину", callback_data='start_quiz')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await query.edit_message_text(text=rules_text, reply_markup=reply_markup)

# Основная функция
def main():
    # Инициализация базы данных
    init_db()
    
    # Создание приложения
    application = Application.builder().token("YOUR_BOT_TOKEN_HERE").build()
    
    # Регистрация обработчиков
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("quiz", quiz))
    application.add_handler(CommandHandler("score", score))
    application.add_handler(CommandHandler("leaderboard", show_leaderboard_command))
    application.add_handler(CommandHandler("rules", rules))
    
    application.add_handler(CallbackQueryHandler(handle_callback))
    
    # Запуск бота
    print("Бот запущен...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()