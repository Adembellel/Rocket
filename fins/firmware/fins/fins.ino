#include <Wire.h>

// MPU6050 I2C Address (0x68 default, 0x69 if AD0 is HIGH)
#define MPU6050_ADDR 0x68

// MPU6050 Register Map
#define PWR_MGMT_1   0x6B
#define GYRO_CONFIG  0x1B
#define ACCEL_CONFIG 0x1C
#define ACCEL_XOUT_H 0x3B

float roll = 0.0;
float pitch = 0.0;
unsigned long lastTime = 0;

// Read multi-byte registers from MPU6050
void readRegisters(uint8_t reg, uint8_t count, uint8_t *dest) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false); // Restart condition
  
  Wire.requestFrom((uint8_t)MPU6050_ADDR, count);
  for (uint8_t i = 0; i < count; i++) {
    if (Wire.available()) {
      dest[i] = Wire.read();
    }
  }
}

// Write single byte to MPU6050 register
void writeRegister(uint8_t reg, uint8_t data) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.write(data);
  Wire.endTransmission();
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Initialize ESP32 I2C (SDA = 21, SCL = 22)
  Wire.begin(21, 22);
  Wire.setClock(400000); // 400kHz I2C speed

  // 1. Wake up MPU6050 (Clear sleep mode bit in PWR_MGMT_1)
  writeRegister(PWR_MGMT_1, 0x00);
  delay(100);

  // 2. Set Gyroscope Full Scale Range to ±500 deg/s (FS_SEL = 1)
  writeRegister(GYRO_CONFIG, 0x08);

  // 3. Set Accelerometer Full Scale Range to ±8g (AFS_SEL = 2)
  writeRegister(ACCEL_CONFIG, 0x10);

  lastTime = millis();
}

void loop() {
  uint8_t rawBuffer[14];
  
  // Read 14 sequential registers: ACCEL (6B), TEMP (2B), GYRO (6B)
  readRegisters(ACCEL_XOUT_H, 14, rawBuffer);

  // Combine High and Low bytes into signed 16-bit integers
  int16_t rawAccX = (int16_t)(rawBuffer[0] << 8 | rawBuffer[1]);
  int16_t rawAccY = (int16_t)(rawBuffer[2] << 8 | rawBuffer[3]);
  int16_t rawAccZ = (int16_t)(rawBuffer[4] << 8 | rawBuffer[5]);
  
  int16_t rawGyroX = (int16_t)(rawBuffer[8] << 8 | rawBuffer[9]);
  int16_t rawGyroY = (int16_t)(rawBuffer[10] << 8 | rawBuffer[11]);

  // Convert raw readings to physical units
  // Sensitivity factors: Accel (+-8g) = 4096 LSB/g, Gyro (+-500 deg/s) = 65.5 LSB/(deg/s)
  float accX = rawAccX / 4096.0;
  float accY = rawAccY / 4096.0;
  float accZ = rawAccZ / 4096.0;

  float gyroX = rawGyroX / 65.5;
  float gyroY = rawGyroY / 65.5;

  // Calculate delta time
  unsigned long currentTime = millis();
  float dt = (currentTime - lastTime) / 1000.0;
  if (dt <= 0.0) dt = 0.001;
  lastTime = currentTime;

  // Calculate Roll and Pitch from Accelerometer
  float accRoll  = atan2(accY, accZ) * 57.29578; // 180 / PI
  float accPitch = atan2(-accX, sqrt(accY * accY + accZ * accZ)) * 57.29578;

  // Complementary Filter (96% Gyro Integration, 4% Accel Angle)
  roll  = 0.96 * (roll + gyroX * dt) + 0.04 * accRoll;
  pitch = 0.96 * (pitch + gyroY * dt) + 0.04 * accPitch;

  // Stream data over Serial to Processing: "roll,pitch"
  Serial.print(roll, 2);
  Serial.print(",");
  Serial.println(pitch, 2);

  delay(10); // ~100Hz refresh rate
}
