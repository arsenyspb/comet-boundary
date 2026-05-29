FROM node:20-alpine
RUN apk add --no-cache curl

WORKDIR /app

# Copy package files first for better caching
COPY package.json package-lock.json ./
RUN npm install

# Copy the rest of the application
COPY . .

EXPOSE 5173

# Vite needs --host to accept connections from outside the container
CMD ["npx", "vite", "--host", "0.0.0.0", "--port", "5173"]
