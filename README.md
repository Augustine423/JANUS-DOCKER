```
docker build -t janus-gateway .
```

```
docker run -d -p 80:80 -p 8088:8088 -p 8188:8188 -p 5002:5002 -p 5004:5004 \
-p 5102:5102 -p 5104:5104 -p 5106:5106 --name janus janus-gateway
```
