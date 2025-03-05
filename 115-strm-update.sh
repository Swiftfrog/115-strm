#!/bin/bash
# 设置 UTF-8 环境，确保字符编码一致
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 配置文件路径，改用$HOME来确保路径正确解析
# 一定要配置url地址，存储目录，详细见附件
config_file="$HOME/.strm/115-strm-update.conf"

# 读取配置文件函数
read_config() {
    if [ -f "$config_file" ]; then
        # shellcheck source=/dev/null
        . "$config_file"
    fi
    update_existing="${update_existing:-1}" # 默认值为 1（跳过）
    delete_absent="${delete_absent:-2}"     # 默认值为 2（不删除）
    last_strm_directory="${last_strm_directory:-}"
    last_interval_time="${last_interval_time:-3}"
    last_user_formats="${last_user_formats:-}"
    exclude_option="${exclude_option:-2}"   # 确保 exclude_option 有默认值
}



# 保存配置文件函数
save_config() {
    cat <<EOF >"$config_file"
directory_tree_file="$directory_tree_file"
directory_tree_url="$directory_tree_url"
strm_save_path="$strm_save_path"
alist_url="$alist_url"
mount_path="$mount_path"
exclude_option="$exclude_option"
custom_extensions="$custom_extensions"
update_existing="$update_existing"
delete_absent="$delete_absent"
last_strm_directory="$last_strm_directory"
last_interval_time="$last_interval_time"
last_user_formats="$last_user_formats"
EOF
}


# 初始化配置
read_config

# 初始化全局变量，存储生成的目录文件路径和自定义扩展名
generated_directory_file="${generated_directory_file:-}"
custom_extensions="${custom_extensions:-}"

# 定义内置的媒体文件扩展名
builtin_audio_extensions=("mp3" "flac" "wav" "aac" "ogg" "wma" "alac" "m4a" "aiff" "ape" "dsf" "dff" "wv" "pcm" "tta")
builtin_video_extensions=("mp4" "mkv" "avi" "mov" "wmv" "flv" "webm" "vob" "mpg" "mpeg")
builtin_image_extensions=("jpg" "jpeg" "png" "gif" "bmp" "tiff" "svg" "heic")
builtin_other_extensions=("iso" "img" "bin" "nrg" "cue" "dvd" "lrc" "srt" "sub" "ssa" "ass" "vtt" "txt" "pdf" "doc" "docx" "csv" "xml" "new")

# 将目录树文件转换为目录文件的函数
convert_directory_tree() {
#    if [ -n "$directory_tree_file" ]; then
#        echo "请输入目录树文件的路径或者下载链接，上次配置:${directory_tree_file}，回车确认："
#    else
#        echo "请输入目录树文件的路径或者下载链接，路径示例：/path/to/alist20250101000000_目录树.txt，回车确认："
#    fi
#    read -r input_directory_tree_file
#    directory_tree_file="${input_directory_tree_file:-$directory_tree_file}"

    directory_tree_file="$directory_tree_url"

    if [[ $directory_tree_file == http* ]]; then
        url="$directory_tree_file"

        filename=$(basename "$url")
        decoded_filename=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$filename'))")

        # 下载文件
        curl -L -o "$filename" "$url"

        # 重命名文件
        mv "$filename" "$decoded_filename"

        # 更新 directory_tree_file 为新下载文件的完整路径
        directory_tree_file="$PWD/$decoded_filename"

        # 保存配置以记录新路径
        save_config
    fi

    if [ ! -f "$directory_tree_file" ]; then
        echo "目录树文件不存在，请提供有效的文件路径。"
        return
    fi

    # 获取目录树文件的目录和文件名
    directory_tree_dir=$(dirname "$directory_tree_file")
    directory_tree_base=$(basename "$directory_tree_file")

    # 转换目录树文件为 UTF-8 格式，以便处理（如有需要）
    converted_file="$directory_tree_dir/$directory_tree_base.converted"
    iconv -f utf-16le -t utf-8 "$directory_tree_file" >"$converted_file"

    # 生成的目录文件路径
    generated_directory_file="${converted_file}_目录文件.txt"

    # 使用 Python 解析目录树
    python3 - <<EOF
import os

def parse_directory_tree(file_path):
    current_path_stack = []
    directory_list_file = "${generated_directory_file}"

    # 打开输入文件和输出文件
    with open(file_path, 'r', encoding='utf-8') as file, \
         open(directory_list_file, 'w', encoding='utf-8') as output_file:
        for line in file:
            # 移除 BOM 和多余空白
            line = line.lstrip('\ufeff').rstrip()
            line_depth = line.count('|')  # 计算目录级别
            item_name = line.split('|-')[-1].strip()  # 获取当前项名称
            if not item_name:
                continue
            while len(current_path_stack) > line_depth:
                current_path_stack.pop()  # 移出多余的路径层级
            if len(current_path_stack) == line_depth:
                if current_path_stack:
                    current_path_stack.pop()
            current_path_stack.append(item_name)  # 添加当前项到路径栈
            full_path = '/' + '/'.join(current_path_stack)  # 构建完整路径
            output_file.write(full_path + '\n')  # 写入输出文件

parse_directory_tree("$converted_file")
EOF
    # 使用 sed 在 bash 中处理生成文件，替换每行开头的 "/|——" 为 "/"
    sed -i 's/^.\{4\}/\//' "${converted_file}_目录文件.txt"

    # 清理临时转换文件
    rm "$converted_file"
    echo "目录文件已生成：$generated_directory_file"

    # 保存配置
    save_config
}

# 生成 .strm 文件的函数
generate_strm_files() {

    # 提示用户输入用于保存 .strm 文件的路径
#    if [ -n "$strm_save_path" ]; then
#        echo "请输入 .strm 文件保存的路径，上次配置:${strm_save_path}，回车确认："
#    else
#        echo "请输入 .strm 文件保存的路径："
#    fi
#    read -r input_strm_save_path
    strm_save_path="${input_strm_save_path:-$strm_save_path}"
    mkdir -p "$strm_save_path"

    # 提示用户输入 alist 的地址加端口
#    if [ -n "$alist_url" ]; then
#        echo "请输入alist的地址+端口（例如：http://abc.com:5244），上次配置:${alist_url}，回车确认："
#    else
#        echo "请输入alist的地址+端口（例如：http://abc.com:5244）："
#    fi
#    read -r input_alist_url
    alist_url="${input_alist_url:-$alist_url}"
    # 确保 URL 的格式正确，以 / 结尾
    if [[ "$alist_url" != */ ]]; then
        alist_url="$alist_url/"
    fi

    # 提示用户输入挂载路径信息
    decoded_mount_path=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('${mount_path}'))")
#    if [ -n "$decoded_mount_path" ]; then
#        echo "请输入alist存储里对应的挂载路径信息，上次配置:${decoded_mount_path}，回车确认："
#    else
#        echo "请输入alist存储里对应的挂载路径信息："
#    fi
#    read -r input_mount_path
    mount_path="${input_mount_path:-$mount_path}"

    # 处理挂载路径的不同输入情况
    if [[ "$mount_path" == "/" ]]; then
        mount_path=""
    elif [[ -n "$mount_path" ]]; then
        # 检查第一个字符是否是 /
        if [[ "${mount_path:0:1}" != "/" ]]; then
            mount_path="/${mount_path}"
        fi
        # 检查最后一个字符是否是 /
        if [[ "${mount_path: -1}" == "/" ]]; then
            mount_path="${mount_path%/}"
        fi
    fi

    # 编码挂载路径
    encoded_mount_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${mount_path}'))")

    # 拼接 URL
    full_alist_url="${alist_url%/}/d${encoded_mount_path}/"

    # 提示用户输入剔除选项，增加默认值为2
#    if [ -n "$exclude_option" ]; then
#        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2），上次配置:${exclude_option}，回车确认："
#    else
#        echo "请输入剔除选项（输入要剔除的目录层级数量，默认为2）："
#    fi
#    read -r input_exclude_option
    exclude_option="${input_exclude_option:-$exclude_option}"

    # 提示选择更新该是跳过
#    echo "如果本次要创建的strm文件已存在，请选择更新还是跳过（上次配置: ${update_existing:-1}）：1. 跳过 2. 更新"
#    read -r input_update_existing
    update_existing="${input_update_existing:-$update_existing}"
    # 提示选择更新该是跳过
#    echo "如果本次目录中存在本次未创建的strm文件，是否删除（上次配置: ${delete_absent:-2}）：1. 删除 2. 不删除"
#    read -r input_delete_absent
    delete_absent="${input_delete_absent:-$delete_absent}"

    # 创建临时文件来存储现有的目录结构
    temp_existing_structure=$(mktemp)
    temp_new_structure=$(mktemp)

    # 获取现有的 .strm 文件目录结构并存入临时文件
    find "$strm_save_path" -type f -name "*.strm" >"$temp_existing_structure"

    # 使用 Python 生成 .strm 文件并处理多线程与进度显示
    python3 - <<EOF
import os
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

# 定义一些变量
update_existing = $update_existing
delete_absent = $delete_absent


# 定义常见的媒体文件扩展名，并合并用户自定义扩展名
media_extensions = set([
    "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "vob", "mpg", "mpeg",
    "iso", "img", "dvd", "ts", "rm", "rmvb", "3gp", "dat", "ogg", "m2ts"
])
custom_extensions = set("${custom_extensions}".split())
media_extensions.update(custom_extensions)

# 设定变量
exclude_option = $exclude_option
alist_url = "$full_alist_url"
strm_save_path = "$strm_save_path"
generated_directory_file = "$generated_directory_file"

# 临时文件路径，存放在当前脚本执行目录
temp_existing_structure = os.path.join("${script_dir}", "existing_structure.txt")
temp_new_structure = os.path.join("${script_dir}", "new_structure.txt")
temp_to_create = os.path.join("${script_dir}", "to_create.txt")
temp_to_delete = os.path.join("${script_dir}", "to_delete.txt")

# 获取现有的 .strm 文件目录结构
def list_existing_files():
    existing_files = []
    for root, _, files in os.walk(strm_save_path):
        for file in files:
            if file.endswith('.strm'):
                existing_files.append(os.path.join(root, file))
    with open(temp_existing_structure, 'w', encoding='utf-8') as f:
        f.writelines(f"{line}\n" for line in existing_files)

# 处理生成目录结构
def process_directory_structure():
    with open(generated_directory_file, 'r', encoding='utf-8') as file, open(temp_new_structure, 'w', encoding='utf-8') as new_structure_file:
        for line in file:
            line = line.strip()
            if line.count('/') < exclude_option + 1:
                continue

            adjusted_path = '/'.join(line.split('/')[exclude_option + 1:])
            if adjusted_path.split('.')[-1].lower() in media_extensions:
                new_structure_file.write(adjusted_path + '\n')

# 根据文件列表创建或更新 .strm 文件
def create_strm_files():
    total = 0
    with open(temp_new_structure, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        total = len(lines)
    
    processed = 0
    lock = threading.Lock()
    with open(temp_to_create, 'w', encoding='utf-8') as to_create_file:
        def process_line(line):
            nonlocal processed
            line = line.strip()
            parent_path, file_name = os.path.split(line)
            strm_file_path = os.path.join(strm_save_path, parent_path, f"{file_name}.strm")
            os.makedirs(os.path.join(strm_save_path, parent_path), exist_ok=True)

            if not os.path.exists(strm_file_path) or update_existing == 2:
                encoded_path = urllib.parse.quote(line)
                with open(strm_file_path, 'w', encoding='utf-8') as strm_file:
                    strm_file.write(f"{alist_url}{encoded_path}")
                to_create_file.write(strm_file_path + '\n')

            with lock:
                processed += 1
                print(f"\r创建 .strm：{processed}/{total} ({processed / total:.2%})", end='')

        with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
            futures = [executor.submit(process_line, line) for line in lines]
            for _ in as_completed(futures):
                pass

# 删除多余的 .strm 文件
def delete_obsolete_files():
    if delete_absent != 1:
        return

    with open(temp_existing_structure, 'r', encoding='utf-8') as existing_file:
        existing_files = set(existing_file.read().splitlines())
    with open(temp_new_structure, 'r', encoding='utf-8') as new_file:
        new_files = {os.path.join(strm_save_path, '/'.join(path.split('/')[:-1]), path.split('/')[-1] + '.strm') for path in new_file.read().splitlines()}
    
    files_to_delete = existing_files - new_files
    total = len(files_to_delete)
    processed = 0
    lock = threading.Lock()

    with open(temp_to_delete, 'w', encoding='utf-8') as to_delete_file:
        def process_deletion(file_path):
            nonlocal processed
            try:
                os.remove(file_path)
                to_delete_file.write(file_path + '\n')
                parent_dir = os.path.dirname(file_path)
                while parent_dir and parent_dir != strm_save_path:
                    try:
                        os.rmdir(parent_dir)
                    except OSError:
                        break
                    parent_dir = os.path.dirname(parent_dir)
            except OSError:
                pass

            with lock:
                processed += 1
                print(f"\r删除 .strm：{processed}/{total} ({processed / total:.2%})", end='')

        with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as executor:
            futures = [executor.submit(process_deletion, file_path) for file_path in files_to_delete]
            for _ in as_completed(futures):
                pass

print("检测现有 .strm 文件...")
list_existing_files()

print("生成新的目录结构...")
process_directory_structure()

print("创建 .strm 文件...")
create_strm_files()

print("\n删除多余的 .strm 文件...")
delete_obsolete_files()

print("\n操作完成。")

EOF

    # 定义当前脚本的执行目录
    script_dir=$(pwd)

    # 清理临时文件
    for temp_file in "existing_structure.txt" "new_structure.txt" "to_create.txt" "to_delete.txt"; do
        temp_file_path="${script_dir}/${temp_file}"
        if [ -f "$temp_file_path" ]; then
            rm "$temp_file_path"
            echo "已删除临时文件：'$temp_file_path'"
        else
            echo "没有检测到需要删除的文件：'$temp_file_path'"
        fi
    done

    # 保存配置
    save_config
}

# 主程序

convert_directory_tree

generate_strm_files
