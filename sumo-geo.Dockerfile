# =============================================================================
# sumo-geo.Dockerfile — visor SUMO-GEO AUTOCONTENIDO (backend + frontend)
#
# Clona el repo SUMO_GEO DURANTE el build (mismo patrón que VAN3TWIN_REPO en
# el Dockerfile de van3twin): los estudiantes solo clonan van3twin-docker.
#
#   docker compose --profile visor up -d --build
#
# Para traer los últimos cambios del repo tras un push (la capa del clone se
# cachea): docker compose --profile visor build --no-cache backend frontend
#
# Desarrollo local (Pablo): docker-compose.dev.yml restaura los bind mounts
# al repo local (editar y recargar, sin rebuild) — se activa con la línea
# COMPOSE_FILE del .env local. Ver docker-compose.dev.yml.
# =============================================================================
ARG SUMO_GEO_REPO=https://github.com/Pbarbecho/SUMO_GEO.git
ARG SUMO_GEO_REF=main

# --- etapa 1: clonar el repo -------------------------------------------------
FROM alpine/git:latest AS clone
ARG SUMO_GEO_REPO
ARG SUMO_GEO_REF
RUN git clone --depth 1 --branch ${SUMO_GEO_REF} ${SUMO_GEO_REPO} /src && \
    git -C /src rev-parse HEAD | tee /src/COMMIT

# --- etapa 2: backend (igual que SUMO_GEO/backend/Dockerfile.van3twin, pero
#     copiando desde el clone en vez del contexto local) ----------------------
FROM python:3.11-slim AS backend
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY --from=clone /src/backend/requirements-van3twin.txt .
RUN pip install --no-cache-dir -r requirements-van3twin.txt
COPY --from=clone /src/backend/app ./app
COPY --from=clone /src/COMMIT /COMMIT
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# --- etapa 3: frontend (nginx con los estáticos horneados en la imagen) ------
FROM nginx:1.27-alpine AS frontend
COPY --from=clone /src/frontend /usr/share/nginx/html
COPY --from=clone /src/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=clone /src/COMMIT /COMMIT
EXPOSE 80
