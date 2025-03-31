import csv
import logging
import re
import time
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# 配置日志
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# 全局变量：存储已处理的 URL
url_index = set()

# 设定webdriver
def setup_driver():
    """配置 Selenium WebDriver"""
    try:
        options = Options()
        options.add_argument("--headless")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36")

        chromedriver_path = "/usr/bin/chromedriver"
        service = Service(chromedriver_path)  # Windows 使用 "NUL"，Linux/macOS 使用 "/dev/null"

        driver = webdriver.Chrome(service=service, options=options)
        logging.info("Selenium WebDriver 初始化成功。")
        return driver
    except Exception:
        logging.error("Selenium WebDriver 初始化失败")
        raise

# 判断是否有CSV
def load_existing_data(csv_file):
    """加载现有的 CSV 数据"""
    try:
        with open(csv_file, mode="r", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            existing_data = list(reader)
            logging.info(f"成功加载现有数据，共 {len(existing_data)} 条记录。")
            return existing_data
    except FileNotFoundError:
        logging.warning("未找到 CSV 文件，初始化为空列表。")
        return []

# 点击按钮
def click_enter_button(driver, timeout=10):
    """
    查找并点击页面上的按钮
    :param driver: Selenium WebDriver 实例
    :param timeout: 最大等待时间（秒）
    """
    try:
        wait = WebDriverWait(driver, timeout)
        enter_button = wait.until(EC.element_to_be_clickable((By.CLASS_NAME, "enter-btn")))
        logging.info("找到按钮并准备点击...")
        enter_button.click()
        logging.info("按钮已成功点击。")
    except Exception as e:
        logging.warning(f"未找到或无法点击按钮: {e}")
        raise  # 继续抛出异常以触发重试

# 读取HTML内容
def fetch_html_with_selenium(url, driver, max_retries=3, first_visit=True):
    """
    获取 HTML 内容
    :param url: 目标网页 URL
    :param driver: Selenium WebDriver 实例
    :param max_retries: 最大重试次数
    :param first_visit: 是否是第一次访问（默认为 True）
    :return: 页面 HTML 内容或 None
    """
    for attempt in range(max_retries):
        try:
            # 访问目标网页
            driver.get(url)
            logging.info(f"尝试 {attempt + 1}/{max_retries}: 正在访问URL: {url}")

            # 等待按钮加载完成并点击
            # 如果是第一次访问，尝试点击按钮
            if first_visit:
                try:
                    click_enter_button(driver)  # 调用独立的按钮点击函数
                except Exception:
                    logging.warning(f"尝试 {attempt + 1}/{max_retries}: 按钮点击失败")
                    raise  # 继续抛出异常以触发重试

            # 等待页面加载完成
            try:
                wait = WebDriverWait(driver, 15, poll_frequency=1)
                torrent_link = wait.until(EC.presence_of_element_located((By.XPATH, "//a[contains(text(), '.torrent')]")))
                logging.info(f"尝试 {attempt + 1}/{max_retries}: 找到 .torrent 字段，页面内容已加载完成。")
            except Exception:
                logging.warning(f"尝试 {attempt + 1}/{max_retries}: 页面内容加载超时或未找到 .torrent 字段")
                raise  # 继续抛出异常以触发重试

            html_content = driver.page_source
            return html_content
        except Exception:
            logging.error(f"尝试 {attempt + 1}/{max_retries} 失败")
            if attempt < max_retries - 1:
                logging.info(f"将在 {2 ** attempt} 秒后重试...")
                time.sleep(2 ** attempt)
            else:
                logging.error("已达到最大重试次数，放弃此URL。")
                return None

def extract_date(soup):
    """提取发表时间"""
    try:
        publish_time_tag = soup.find("em", id=lambda x: x and x.startswith("authorposton"))
        if not publish_time_tag:
            logging.warning("未找到发表时间标签，返回默认值 'N/A'。")
            return "N/A"

        em_text = publish_time_tag.get_text(strip=True).replace("发表于", "").strip()
        if re.match(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", em_text):
            return em_text

        span_tag = publish_time_tag.find("span", title=lambda x: x and "-" in x)
        if span_tag:
            return span_tag.get("title").strip()

        logging.warning("发表时间格式不匹配，返回默认值 'N/A'。")
        return "N/A"
    except Exception:
        logging.error("提取发表时间失败")
        return "N/A"

def extract_data(html_content, url):
    """解析 HTML 并提取数据"""
    try:
        soup = BeautifulSoup(html_content, 'html.parser')

        date = extract_date(soup)

        torrent_tag = soup.find("a", string=lambda text: text and ".torrent" in text)
        number = torrent_tag.get_text(strip=True)[:-8] if torrent_tag else "N/A"

        title_tag = soup.find(string=lambda t: t and "影片名称" in t)
        title = title_tag.split("：")[1].strip() if title_tag else "N/A"

        type_tag = soup.find(string=lambda t: t and "是否有码" in t)
        type_value = type_tag.split("：")[1].strip() if type_tag else "N/A"

        size_tag = soup.find(string=lambda t: t and "影片容量" in t)
        size = size_tag.split("：")[1].strip() if size_tag else "N/A"

        magnet_tag = soup.find("div", class_="blockcode")
        magnet = magnet_tag.find("li").get_text(strip=True) if magnet_tag and magnet_tag.find("li") else "N/A"

        logging.info(f"成功提取数据: 编号={number}, 标题={title}, 容量={size}, 类型={type_value}, 磁力链接={magnet}")
        return {
            "date": date,
            "number": number,
            "title": title,
            "size": size,
            "type": type_value,
            "magnet": magnet,
            "LINK": url  # 将 URL 作为 LINK 字段
        }
    except Exception:
        logging.error("数据提取失败")
        return None

def load_url_index(index_file="url_index.csv"):
    """加载 URL 索引文件到内存"""
    global url_index
    try:
        with open(index_file, mode="r", encoding="utf-8") as file:
            reader = csv.reader(file)
            url_index = {row[0] for row in reader}
            logging.info(f"成功加载 URL 索引文件，共 {len(url_index)} 条记录。")
    except FileNotFoundError:
        logging.warning("未找到 URL 索引文件，初始化为空集合。")
        url_index = set()

def is_duplicate(url):
    """检查 URL 是否已存在"""
    if url in url_index:
        logging.info(f"URL 已处理过，跳过: {url}")
        return True
    return False

def update_url_index(urls, index_file="url_index.csv"):
    """更新 URL 索引文件"""
    global url_index
    new_urls = []

    for url in urls:
        if url not in url_index:
            new_urls.append(url)
            url_index.add(url)

    if new_urls:
        with open(index_file, mode="a", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerows([[url] for url in new_urls])
        logging.info(f"成功更新 URL 索引文件，新增 {len(new_urls)} 条记录。")

def update_csv(data_list, csv_file, existing_data, insert_mode=False):
    """更新 CSV 文件"""

    fieldnames = ["NO.", "date", "number", "title", "size", "type", "magnet", "LINK"]

    # 去重：确保新数据不会重复插入
    seen_magnets = {data["magnet"] for data in existing_data}
    filtered_new_data = []

    for data in data_list:
        if data["magnet"] in seen_magnets:
            logging.info(f"发现重复数据，跳过写入: URL={data['LINK']}, Magnet={data['magnet']}")
            # 如果发现重复，直接返回，不再继续处理
            return False
        else:
            filtered_new_data.append(data)

    # 如果没有新数据需要写入，直接返回
    if not filtered_new_data:
        logging.info("没有新数据需要写入，退出更新操作。")
        return False

    # 合并数据
    if insert_mode:
        updated_data = filtered_new_data + existing_data  # 插入模式：新数据在前
    else:
        updated_data = existing_data + filtered_new_data  # 顺序模式：新数据在后

    # 重新编号
    for i, data in enumerate(updated_data, start=1):
        data["NO."] = str(i)

    # 写入 CSV 文件
    with open(csv_file, mode="w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(updated_data)

    logging.info(f"成功更新 CSV 文件，共写入 {len(updated_data)} 条记录。")
    return True

def main():
    input_csv = "input.csv"
    output_csv = "output.csv"
    index_file = "url_index.csv"  # URL 索引文件
    batch_size = 1  # 示例：单条写入

    # 加载 URL 索引文件
    load_url_index(index_file)

    # 加载现有数据，并初始化 insert_mode
    existing_data = load_existing_data(output_csv)
    insert_mode = len(existing_data) > 0  # 如果有数据，则启用插入模式

    # 读取输入文件
    urls = []
    try:
        with open(input_csv, mode="r", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            if "URL" not in reader.fieldnames:
                logging.error("输入文件缺少 'URL' 列，请检查文件格式。")
                return
            urls = [row["URL"] for row in reader]
    except FileNotFoundError:
        logging.error(f"未找到输入文件 {input_csv}，请检查文件路径。")
        return

    if not urls:
        logging.warning("未找到任何URL，请检查输入的CSV文件。")
        return

    # 初始化 WebDriver
    driver = setup_driver()
    try:

        # 标志变量：是否是第一次访问
        first_visit_flag = True

        batch_data = []
        for i, url in enumerate(urls):
            logging.info(f"正在处理URL ({i + 1}/{len(urls)}): {url}")

            # 检查是否重复（基于 URL 字段）
            if is_duplicate(url):
                continue
            # 获取 HTML 内容
            html_content = fetch_html_with_selenium(url, driver, first_visit=first_visit_flag)

            # 如果是第一次访问且成功获取内容，则更新标志变量
            if first_visit_flag and html_content:
                first_visit_flag = False

#            html_content = fetch_html_with_selenium(url, driver)
            if not html_content:
                logging.error(f"无法获取HTML内容，跳过URL: {url}")
                continue

            data = extract_data(html_content, url)
            if not data:
                logging.error(f"数据提取失败，跳过URL: {url}")
                continue

            batch_data.append(data)

            # 如果达到批量大小，则写入 CSV 文件
            if len(batch_data) >= batch_size:
                success = update_csv(batch_data, output_csv, existing_data, insert_mode=insert_mode)
                if success:
                    update_url_index([data["LINK"] for data in batch_data], index_file)
                    logging.info(f"已写入 {batch_size} 条数据到 {output_csv} 文件中！")
                batch_data.clear()

        # 写入剩余数据（如果有）
        if batch_data:
            success = update_csv(batch_data, output_csv, existing_data, insert_mode=insert_mode)
            if success:
                update_url_index([data["LINK"] for data in batch_data], index_file)
                logging.info(f"已写入剩余 {len(batch_data)} 条数据到 {output_csv} 文件中！")
    finally:
        driver.quit()

if __name__ == "__main__":
    main()
