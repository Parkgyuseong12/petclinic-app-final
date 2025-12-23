# Nginx를 사용하여 정적 파일 서빙
# EKS는 x86_64 아키텍처를 사용하므로 플랫폼 명시
FROM --platform=linux/amd64 nginx:alpine

# 정적 파일들을 Nginx html 폴더로 복사
# 빌드 컨텍스트가 프로젝트 루트인 경우
COPY spring-petclinic-api-gateway/src/main/resources/static/ /usr/share/nginx/html/

# Nginx 설정 파일 복사
COPY spring-petclinic-frontend/nginx.conf /etc/nginx/conf.d/default.conf

# 포트 노출
EXPOSE 80

# Nginx 실행
CMD ["nginx", "-g", "daemon off;"]

