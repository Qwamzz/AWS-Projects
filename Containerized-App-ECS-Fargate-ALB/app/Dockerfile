# Pulled from Amazon ECR Public to avoid Docker Hub rate limits
FROM public.ecr.aws/docker/library/python:3.12-slim

ARG APP_VERSION=1
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1

WORKDIR /app
COPY app.py .

# Run as a non-root user
RUN useradd --create-home appuser
USER appuser

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"
CMD ["python", "app.py"]
