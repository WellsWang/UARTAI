#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include "time.h"

#define CONN_LED 33 

const char* SSID = "YOUR_WIFI_SSID";
const char* PASSWORD = "YOUR_WIFI_PASSWORD";
const char* API_KEY = "YOUR_DEEPSEEK_API_KEY";

// NTP 配置
const char* ntpServer = "pool.ntp.org";
const long gmtOffset_sec = 8 * 3600;  // GMT+8，如需其他时区请修改
const int daylightOffset_sec = 0;

String res= "";

//unsigned long startTime;

void setup() {
  pinMode(CONN_LED, OUTPUT);
  digitalWrite(CONN_LED, HIGH);
  Serial.begin(9600);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();

  delay(1000);

  while (!Serial)
    ;

  WiFi.mode(WIFI_STA);
  WiFi.begin(SSID, PASSWORD);
  Serial.print("Connecting: ");
  Serial.println(SSID);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    //Serial.print(WiFi.status());
    Serial.print(".");
  }
  Serial.println("\nConnected to WiFi.");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
  digitalWrite(CONN_LED, LOW);

  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
  Serial.println("NTP synced.");
}


void loop() {
  Serial.print("[Please Ask Question] ");
  
  char c = 0;

  while (c!=13) {
    while (!Serial.available()) 
      ;

    while (Serial.available()) {
      c = Serial.read();
      res += c;
//      delay(10);
    }
  }

  int len = res.length();
  res = res.substring(0, len - 1);
  res.trim();
  if (res == "#GETTIME#") {
    delay(1000);
    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
      Serial.println("## GET TIME ERROR ##");
      return;
    }

    char formattedTime[15]; // YYYYMMDDHHMMSS + '\0'
    snprintf(formattedTime, sizeof(formattedTime), "%04d%02d%02d%02d%02d%02d",
              timeinfo.tm_year + 1900,
              timeinfo.tm_mon + 1,
              timeinfo.tm_mday,
              timeinfo.tm_hour,
              timeinfo.tm_min,
              timeinfo.tm_sec);

    Serial.println(formattedTime);
  }
  else {

    res = "\"" + res + "\"";
    Serial.println(res);

    HTTPClient https;

    if (https.begin("https://api.deepseek.com/chat/completions")) {
      https.addHeader("Content-Type", "application/json");
      String token_key = String("Bearer ") + API_KEY;
      https.addHeader("Authorization", token_key);

      String payload = String("{\"model\": \"deepseek-chat\", \"messages\": [{\"role\": \"user\", \"content\": ") + res + String("}]}");
      Serial.print("Payload: ");
      //Serial.println(payload);
      res = "";

      int httpCode = https.POST(payload);

      if ( httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_MOVED_PERMANENTLY) {
        Serial.println("Response received. Reading payload, Please waiting...");

        String response = "";
        WiFiClient* stream = https.getStreamPtr();
        unsigned long lastReadTime = millis();
        const unsigned long timeoutPeriod = 15000;

        while (true){
          while (stream->available()){
            char c = stream->read();
            response += c;
            lastReadTime = millis();
          }

          if (millis() - lastReadTime > timeoutPeriod){
            break;
          }
        }

        response = response.substring(4);

        JsonDocument doc;

        DeserializationError error = deserializeJson(doc, response);

        if (error){
          Serial.print("Deserialize JSON failed: ");
          Serial.println(error.c_str());
          Serial.println(response);
          return;
        }
        String answer = doc["choices"][0]["message"]["content"];

        Serial.print("Answer: ");
        for (int i=0; i<answer.length();i++){
          if (answer[i] == 10) 
            Serial.write(13);       
          else 
            Serial.print(answer[i]);
        }
        Serial.println("");
      } else {
        Serial.printf("[HTTPS] POST failed, error: %s\n", https.errorToString(httpCode).c_str());
      }

      https.end();

    } else {
      Serial.println("[HTTPS] Unable to connect.");
    }

    Serial.println("Wait 10s before next round ...");
  }
  res = "";
}
