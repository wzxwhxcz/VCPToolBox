# =================================================================
# Stage 1: Build Stage - 用于编译和安装所有依赖
# =================================================================
FROM node:20-alpine AS build

# 设置工作目录
WORKDIR /usr/src/app

# 安装基础工具
RUN apk add --no-cache \
  python3 \
  py3-pip \
  make \
  g++ \
  git

# 复制 package.json 和 package-lock.json
COPY package*.json ./

# 安装主项目依赖
RUN npm ci || npm install

# 复制 Python 依赖文件（如果存在）
COPY requirements.txt ./
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt || true

# 复制所有源代码
COPY . .

# 查找并安装插件的 npm 依赖（简化版本，忽略错误）
RUN for dir in Plugin/*/; do \
    if [ -f "$dir/package.json" ]; then \
        echo "Installing dependencies in $dir"; \
        (cd "$dir" && npm install --legacy-peer-deps) || echo "Warning: Failed to install deps in $dir"; \
    fi; \
done

# 查找并安装插件的 Python 依赖（忽略错误）
RUN for req in Plugin/*/requirements.txt; do \
    if [ -f "$req" ]; then \
        echo "Installing Python deps from $req"; \
        pip3 install --no-cache-dir --break-system-packages -r "$req" || echo "Warning: Failed to install $req"; \
    fi; \
done

# =================================================================
# Stage 2: Production Stage - 最终的轻量运行环境
# =================================================================
FROM node:20-alpine

# 设置工作目录
WORKDIR /usr/src/app

# 安装运行时依赖
RUN apk add --no-cache \
  python3 \
  py3-pip \
  tzdata \
  chromium \
  nss \
  freetype \
  harfbuzz \
  ttf-freefont

# 设置时区
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
  echo "Asia/Shanghai" > /etc/timezone

# 设置环境变量
ENV PYTHONPATH=/usr/src/app
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV PUPPETEER_SKIP_DOWNLOAD=true

# 从构建阶段复制应用和依赖
COPY --from=build /usr/src/app /usr/src/app

# 创建必要的目录
RUN mkdir -p \
  /usr/src/app/VCPTimedContacts \
  /usr/src/app/dailynote \
  /usr/src/app/image \
  /usr/src/app/file \
  /usr/src/app/TVStxt \
  /usr/src/app/VCPAsyncResults \
  /usr/src/app/Plugin/VCPLog/log \
  /usr/src/app/Plugin/EmojiListGenerator/generated_lists \
  /usr/src/app/DebugLog

# 暴露端口
EXPOSE 6005

# 启动命令
CMD ["node", "server.js"]
