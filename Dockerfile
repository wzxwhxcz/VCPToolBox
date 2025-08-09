# =================================================================
# Stage 1: Build
# =================================================================
FROM node:20-alpine AS build
WORKDIR /usr/src/app

# 加速源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# 关键：补齐 git 与 sharp 所需的 vips-dev；并保留构建链
RUN apk add --no-cache \
  tzdata python3 py3-pip build-base gfortran musl-dev \
  lapack-dev openblas-dev jpeg-dev zlib-dev freetype-dev python3-dev \
  linux-headers libffi-dev openssl-dev \
  git pkgconfig vips-dev

# puppeteer 不下载 chromium
ARG PUPPETEER_SKIP_DOWNLOAD=true
ENV PUPPETEER_SKIP_DOWNLOAD=${PUPPETEER_SKIP_DOWNLOAD}

# 用官方 npm 源更稳定；并减少 peer 冲突噪音
ENV NPM_CONFIG_REGISTRY=https://registry.npmjs.org
ENV npm_config_fund=false npm_config_audit=false

COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev --legacy-peer-deps

COPY requirements.txt ./
RUN pip3 install --no-cache-dir --break-system-packages \
    --target=/usr/src/app/pydeps \
    -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt

COPY . .

# 逐插件安装：打印出失败的目录，便于定位
RUN set -eux; \
  for pkg in $(find Plugin -name package.json || true); do \
    d="$(dirname "$pkg")"; \
    echo ">>> Installing Node deps in $d"; \
    (cd "$d" && npm install --omit=dev --legacy-peer-deps) || { echo "!!! Failed in $d"; exit 1; }; \
  done

# =================================================================
# Stage 2: Runtime
# =================================================================
FROM node:20-alpine
WORKDIR /usr/src/app
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
  apk add --no-cache chromium nss freetype harfbuzz ttf-freefont tzdata \
                      python3 openblas jpeg zlib freetype libffi

ENV PYTHONPATH=/usr/src/app/pydeps
# Alpine 的可执行一般是 chromium-browser（也可能是 chromium，自测下）
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone

COPY --from=build /usr/src/app/node_modules ./node_modules
COPY --from=build /usr/src/app/package*.json ./
COPY --from=build /usr/src/app/pydeps ./pydeps
COPY --from=build /usr/src/app/*.js ./
COPY --from=build /usr/src/app/Plugin ./Plugin
COPY --from=build /usr/src/app/Agent ./Agent
COPY --from=build /usr/src/app/routes ./routes
COPY --from=build /usr/src/app/requirements.txt ./

RUN mkdir -p /usr/src/app/VCPTimedContacts \
             /usr/src/app/dailynote \
             /usr/src/app/image \
             /usr/src/app/file \
             /usr/src/app/TVStxt \
             /usr/src/app/VCPAsyncResults \
             /usr/src/app/Plugin/VCPLog/log \
             /usr/src/app/Plugin/EmojiListGenerator/generated_lists

# 端口改为 VCP 实际用到的两个：HTTP 和 WebSocket
EXPOSE 5890 8088

# 如果你确认用 pm2，保证 package.json 里含 pm2 依赖；否则用 node 直接起
CMD ["node_modules/.bin/pm2-runtime","start","server.js"]
# 或：CMD ["node","server.js"]
