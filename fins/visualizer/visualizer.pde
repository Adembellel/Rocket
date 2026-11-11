import processing.serial.*;

Serial myPort;

// Telemetry Targets & Interpolated Values
float targetRoll = 0, targetPitch = 0;
float currentRoll = 0, currentPitch = 0;

float[] targetFins  = new float[3];
float[] currentFins = new float[3];

boolean serialConnected = false;

void setup() {
  size(1000, 750, P3D);
  smooth(8);
  
  println("--- Available Serial Ports ---");
  printArray(Serial.list());
  println("------------------------------");

  try {
    // Select your ESP32 COM port index (e.g. Serial.list()[0] or "COM5")
    String portName = Serial.list()[0]; 
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n');
    myPort.clear();
    serialConnected = true;
  } catch (Exception e) {
    println("Failed to open port. Check COM index.");
    serialConnected = false;
  }
}

void draw() {
  background(15, 18, 28);
  
  // Interpolation for 60 FPS visual smoothness
  currentRoll  = lerp(currentRoll, targetRoll, 0.25);
  currentPitch = lerp(currentPitch, targetPitch, 0.25);
  for (int i = 0; i < 3; i++) {
    currentFins[i] = lerp(currentFins[i], targetFins[i], 0.3);
  }

  // Lighting
  ambientLight(70, 75, 90);
  directionalLight(255, 255, 255, 0.6, 1, -0.8);
  pointLight(255, 120, 40, width/2, height/2 + 100, 150);

  // Center Scene
  pushMatrix();
  translate(width / 2, height / 2 - 20, 0);
  
  // Apply Rocket Attitude (YAW, PITCH, ROLL)
  rotateX(radians(-currentPitch));
  rotateZ(radians(currentRoll));
  
  // Render Rocket Body & 3 Dynamic Servo Fins
  drawRocketWithFins();
  
  popMatrix();

  // Draw 2D Dashboard
  drawHUD();
}

void drawRocketWithFins() {
  noStroke();

  // 1. Main Fuselage Body
  pushMatrix();
  fill(230, 235, 245);
  drawCylinder(26, 26, 220, 24);
  popMatrix();

  // 2. Nose Cone
  pushMatrix();
  translate(0, -110, 0);
  fill(220, 40, 40);
  drawCone(26, 70, 24);
  popMatrix();

  // 3. Accent Ring
  pushMatrix();
  translate(0, -45, 0);
  fill(35, 40, 50);
  drawCylinder(26.5, 26.5, 18, 24);
  popMatrix();

  // 4. Engine Nozzle
  pushMatrix();
  translate(0, 115, 0);
  fill(60, 65, 75);
  drawCylinder(20, 14, 25, 20);
  popMatrix();

  // 5. RENDER 3 DYNAMIC SERVO FINS (Spaced 120 degrees apart)
  for (int i = 0; i < 3; i++) {
    pushMatrix();
    // Position fin around base (120 deg steps: 0°, 120°, 240°)
    rotateY(radians(i * 120));
    translate(26, 75, 0); // Move to outer edge of fuselage
    
    // Draw Hinge Shaft (Servo Shaft)
    fill(200, 200, 200);
    drawCylinder(3, 3, 10, 8);
    
    // ROTATE FIN ACCORDING TO REAL-TIME SERVO DEFLECTION
    // Rotation occurs along the radial axis (hinge line)
    rotateX(radians(currentFins[i]));

    // Render Fin Geometry
    fill(230, 50, 50);
    beginShape(TRIANGLES);
    // Outer side
    vertex(0, -35, 0);
    vertex(38, 35, 0);
    vertex(0, 30, 0);
    
    // Inner side for 3D thickness
    vertex(0, -35, -2);
    vertex(38, 35, 0);
    vertex(0, 30, -2);
    endShape();
    
    popMatrix();
  }
}

// Custom Mesh Builders
void drawCylinder(float topR, float bottomR, float h, int sides) {
  float angleStep = TWO_PI / sides;
  beginShape(QUAD_STRIP);
  for (int i = 0; i <= sides; i++) {
    float a = i * angleStep;
    vertex(topR * cos(a), -h/2, topR * sin(a));
    vertex(bottomR * cos(a), h/2, bottomR * sin(a));
  }
  endShape();
}

void drawCone(float baseR, float h, int sides) {
  float angleStep = TWO_PI / sides;
  beginShape(TRIANGLES);
  for (int i = 0; i < sides; i++) {
    float a1 = i * angleStep;
    float a2 = (i + 1) * angleStep;
    vertex(0, -h, 0);
    vertex(baseR * cos(a1), 0, baseR * sin(a1));
    vertex(baseR * cos(a2), 0, baseR * sin(a2));
  }
  endShape();
}

// -------------------------------------------------------------
// SERIAL TELEMETRY PARSER & HUD OVERLAY
// -------------------------------------------------------------
void serialEvent(Serial port) {
  try {
    String inString = port.readStringUntil('\n');
    if (inString != null) {
      inString = trim(inString);
      String[] data = split(inString, ',');
      if (data.length == 5) {
        targetRoll     = float(data[0]);
        targetPitch    = float(data[1]);
        targetFins[0]  = float(data[2]);
        targetFins[1]  = float(data[3]);
        targetFins[2]  = float(data[4]);
      }
    }
  } catch (Exception e) {
    // Ignore dropped packets
  }
}

void drawHUD() {
  camera();
  hint(DISABLE_DEPTH_TEST);
  
  // Dashboard background
  fill(15, 20, 30, 220);
  stroke(45, 55, 75);
  rect(15, 15, 270, 160, 8);

  fill(255);
  textSize(14);
  text("ROCKET TELEMETRY & FINS", 30, 38);
  
  textSize(13);
  fill(200, 220, 255);
  text("ROLL:  " + nf(currentRoll, 0, 2) + "°", 30, 62);
  text("PITCH: " + nf(currentPitch, 0, 2) + "°", 30, 82);

  // Fin Angles Display
  stroke(60, 70, 90);
  line(30, 93, 260, 93);
  
  fill(255, 180, 80);
  text("FIN 0 (GPIO 18): " + nf(currentFins[0], 0, 1) + "°", 30, 115);
  text("FIN 1 (GPIO 19): " + nf(currentFins[1], 0, 1) + "°", 30, 133);
  text("FIN 2 (GPIO 23): " + nf(currentFins[2], 0, 1) + "°", 30, 151);

  // Connection dot
  fill(serialConnected ? color(50, 220, 100) : color(230, 50, 50));
  noStroke();
  ellipse(265, 34, 10, 10);
  
  hint(ENABLE_DEPTH_TEST);
}
