# Use Node.js 18 slim image for a lightweight base
FROM node:18-slim

# Set working directory
WORKDIR /app

# Copy package.json and install dependencies
COPY package.json ./
RUN npm install --production && npm cache clean --force

# Copy application code
COPY server.js ./

# Create a non-root user for security
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# Expose port 8080
EXPOSE 8080

# Start the application
CMD ["npm", "start"]