#include <Wire.h>
#include <ESP32Servo.h>   // Library Manager: "ESP32Servo"

// ---------- MPU-6050 ----------
#define MPU6050_ADDR 0x68
#define PWR_MGMT_1   0x6B
#define GYRO_CONFIG  0x1B
#define ACCEL_CONFIG 0x1C
#define ACCEL_XOUT_H 0x3B

const float GYRO_LSB   = 65.5;     // LSB per deg/s at ±500 deg/s
const float ACCEL_LSB  = 4096.0;   // LSB per g at ±8 g
const float RAD_TO_DEG = 57.29578;

// ---------- Fins ----------
const int NUM_FINS       = 4;
const int FIN_PINS[NUM_FINS] = {18, 19, 23, 25};
const int FIN_NEUTRAL    = 90;     // servo angle for a centered fin
const float FIN_LIMIT    = 20.0;   // max deflection in degrees

// Calibration values: change these after the calibration steps below
int trim[NUM_FINS] = {0, 0, 0, 0};  // degrees added to neutral (fixes a crooked fin)
int dir[NUM_FINS]  = {1, 1, 1, 1};  // +1 or -1 (fixes a fin that deflects the wrong way)

// ---------- Control ----------
const float KD = 0.4;               // rate gain, start small
const unsigned long LOOP_US = 2000; // 500 Hz

// ---------- State ----------
Servo fins[NUM_FINS];
float gyroBiasX = 0, gyroBiasY = 0;
float roll = 0, pitch = 0;
unsigned long lastUs = 0;
unsigned int printCounter = 0;

void readRegisters(uint8_t reg, uint8_t count, uint8_t *dest) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU6050_ADDR, count);
  for (uint8_t i = 0; i < count; i++) {
    dest[i] = Wire.read();
  }
}

void writeRegister(uint8_t reg, uint8_t data) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.write(data);
  Wire.endTransmission();
}

void calibrateGyro() {
  const int N = 1000;
  long sumX = 0, sumY = 0;
  uint8_t buf[14];
  for (int i = 0; i < N; i++) {
    readRegisters(ACCEL_XOUT_H, 14, buf);
    sumX += (int16_t)(buf[8]  << 8 | buf[9]);
    sumY += (int16_t)(buf[10] << 8 | buf[11]);
    delay(2);
  }
  gyroBiasX = sumX / (float)N;
  gyroBiasY = sumY / (float)N;
}

// Move one fin to a given angle, applying its trim and direction
void setFin(int i, float cmd) {
  float angle = FIN_NEUTRAL + trim[i] + dir[i] * cmd;
  angle = constrain(angle, 10, 170);  // safety margin from servo stops
  fins[i].write((int)angle);
}

// ---------- Serial calibration commands ----------
// "t <fin> <deg>" set trim for one fin (-20 to 20)
// "p"             print current trim and direction values
// "s"             sweep each fin on its own (bench only)
void handleSerial() {
  if (!Serial.available()) return;
  String line = Serial.readStringUntil('\n');
  line.trim();

  if (line.startsWith("t ")) {
    int id, val;
    if (sscanf(line.c_str(), "t %d %d", &id, &val) == 2 && id >= 0 && id < NUM_FINS) {
      trim[id] = constrain(val, -20, 20);
      setFin(id, 0);
      Serial.print("trim fin "); Serial.print(id);
      Serial.print(" = "); Serial.println(trim[id]);
    }
  } else if (line == "p") {
    for (int i = 0; i < NUM_FINS; i++) {
      Serial.print("fin "); Serial.print(i);
      Serial.print(" trim "); Serial.print(trim[i]);
      Serial.print(" dir "); Serial.println(dir[i]);
    }
  } else if (line == "s") {
    sweepTest();
  }
}

void sweepTest() {
  for (int i = 0; i < NUM_FINS; i++) {
    Serial.print("testing fin "); Serial.println(i);
    setFin(i, 10);  delay(400);
    setFin(i, -10); delay(400);
    setFin(i, 0);   delay(300);
  }
  Serial.println("sweep done");
}

void setup() {
  Serial.begin(115200);
  delay(500);

  Wire.begin(21, 22);
  Wire.setClock(400000);

  writeRegister(PWR_MGMT_1, 0x00);
  delay(100);
  writeRegister(GYRO_CONFIG, 0x08);
  writeRegister(ACCEL_CONFIG, 0x10);

  for (int i = 0; i < NUM_FINS; i++) {
    fins[i].attach(FIN_PINS[i], 500, 2400);
    setFin(i, 0);
  }

  calibrateGyro();   // keep the rocket still for about 2 seconds
  lastUs = micros();
  Serial.println("ready");
}

void loop() {
  handleSerial();

  unsigned long now = micros();
  if (now - lastUs < LOOP_US) return;
  float dt = (now - lastUs) / 1000000.0;
  lastUs = now;

  uint8_t buf[14];
  readRegisters(ACCEL_XOUT_H, 14, buf);

  float accX = (int16_t)(buf[0] << 8 | buf[1]) / ACCEL_LSB;
  float accY = (int16_t)(buf[2] << 8 | buf[3]) / ACCEL_LSB;
  float accZ = (int16_t)(buf[4] << 8 | buf[5]) / ACCEL_LSB;

  float gyroX = ((int16_t)(buf[8]  << 8 | buf[9])  - gyroBiasX) / GYRO_LSB;
  float gyroY = ((int16_t)(buf[10] << 8 | buf[11]) - gyroBiasY) / GYRO_LSB;

  float accMag   = sqrt(accX * accX + accY * accY + accZ * accZ);
  float accRoll  = atan2(accY, accZ) * RAD_TO_DEG;
  float accPitch = atan2(-accX, sqrt(accY * accY + accZ * accZ)) * RAD_TO_DEG;
  float alpha = (fabs(accMag - 1.0) < 0.1) ? 0.02 : 0.0;

  roll  = (1.0 - alpha) * (roll  + gyroX * dt) + alpha * accRoll;
  pitch = (1.0 - alpha) * (pitch + gyroY * dt) + alpha * accPitch;

  // Roll damping: all four fins get the same command, with per-fin direction
  float cmd = constrain(-KD * gyroX, -FIN_LIMIT, FIN_LIMIT);
  for (int i = 0; i < NUM_FINS; i++) {
    setFin(i, cmd);
  }

  // Telemetry for the Processing viewer (no commas in other messages)
  if (++printCounter % 5 == 0) {
    Serial.print(roll, 2);
    Serial.print(",");
    Serial.println(pitch, 2);
  }
}
