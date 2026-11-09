import processing.serial.*;

Serial myPort;

// Sensor data and smoothing targets
float targetRoll = 0, targetPitch = 0;
float currentRoll = 0, currentPitch = 0;
boolean serialConnected = false;

// Particle system for rocket thrust
ArrayList<Particle> particles;

void setup() {
  size(1000, 750, P3D);
  smooth(8);
  pixelDensity(1);
  particles = new ArrayList<Particle>();

  println("--- Available Serial Ports ---");
  printArray(Serial.list());
  println("------------------------------");

  // Automatically select port or specify exact COM port string
  try {
    // Replace index [0] with your ESP32 port (e.g., "COM5" or Serial.list()[1])
    String portName = Serial.list()[0];
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n');
    myPort.clear();
    serialConnected = true;
  } catch (Exception e) {
    println("Failed to open serial port! Verify connection and port index.");
    serialConnected = false;
  }
}

void draw() {
  background(10, 14, 23);

  // Interpolate angles for smooth motion (60 FPS rendering)
  currentRoll = lerp(currentRoll, targetRoll, 0.2);
  currentPitch = lerp(currentPitch, targetPitch, 0.2);

  // Setup 3D Scene Lighting
  ambientLight(60, 65, 80);
  directionalLight(255, 245, 230, 0.5, 1, -0.8);
  pointLight(255, 120, 30, width/2, height/2 + 100, 100);

  // Move origin to viewport center
  pushMatrix();
  translate(width / 2, height / 2 - 20, 0);

  // Apply rotations according to aerospace conventions
  rotateX(radians(currentPitch));
  rotateZ(radians(currentRoll));

  // Render High-Detail Rocket Model
  drawProfessionalRocket();

  // Generate & Update Exhaust Particles
  for (int i = 0; i < 3; i++) {
    particles.add(new Particle(0, 130, 0));
  }
  popMatrix();

  // Render Exhaust Particles in World Space
  updateAndDrawParticles();

  // Draw 2D HUD Dashboard Overlay
  drawHUD();
}

// -------------------------------------------------------------
// 3D ROCKET GRAPHICS PIPELINE
// -------------------------------------------------------------
void drawProfessionalRocket() {
  noStroke();

  // 1. Core Metallic Fuselage
  pushMatrix();
  fill(230, 235, 240);
  specular(180, 180, 180);
  shininess(15.0);
  drawCylinder(24, 24, 200, 24);
  popMatrix();

  // 2. Command Module Nose Cone
  pushMatrix();
  translate(0, -100, 0);
  fill(220, 40, 40);
  drawCone(24, 70, 24);
  popMatrix();

  // 3. Rocket Stage Stripes & Cockpit Glass Ring
  pushMatrix();
  translate(0, -40, 0);
  fill(30, 35, 45);
  drawCylinder(24.5, 24.5, 20, 24);
  popMatrix();

  // 4. Twin Side Booster Pods
  for (int angle = 0; angle < 360; angle += 180) {
    pushMatrix();
    rotateY(radians(angle));
    translate(32, 20, 0);
    fill(200, 205, 215);
    drawCylinder(10, 10, 120, 16); // Booster body

    translate(0, -60, 0);
    fill(220, 40, 40);
    drawCone(10, 25, 16); // Booster nose
    popMatrix();
  }

  // 5. Aerodynamic Stabilizer Fins (4-way symmetry)
  fill(220, 40, 40);
  for (int i = 0; i < 4; i++) {
    pushMatrix();
    rotateY(HALF_PI * i);
    translate(24, 70, 0);

    beginShape(TRIANGLES);
    vertex(0, -40, 0);
    vertex(35, 40, 0);
    vertex(0, 30, 0);

    vertex(0, -40, 0);
    vertex(0, 30, 0);
    vertex(-5, 30, -2);
    endShape();
    popMatrix();
  }

  // 6. Main Engine Nozzle
  pushMatrix();
  translate(0, 105, 0);
  fill(60, 65, 75);
  drawCylinder(18, 12, 25, 20);
  popMatrix();
}

// Custom mesh utilities
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
// EXHAUST PARTICLE SYSTEM
// -------------------------------------------------------------
void updateAndDrawParticles() {
  hint(DISABLE_DEPTH_TEST);
  for (int i = particles.size() - 1; i >= 0; i--) {
    Particle p = particles.get(i);
    p.update();
    p.display();
    if (p.isDead()) {
      particles.remove(i);
    }
  }
  hint(ENABLE_DEPTH_TEST);
}

class Particle {
  PVector pos, vel;
  float lifespan, maxLife;
  float size;

  Particle(float x, float y, float z) {
    pos = new PVector(x + random(-4, 4), y + random(0, 5), z + random(-4, 4));
    vel = new PVector(random(-0.5, 0.5), random(4, 9), random(-0.5, 0.5));
    lifespan = maxLife = random(20, 40);
    size = random(8, 18);
  }

  void update() {
    pos.add(vel);
    lifespan--;
  }

  void display() {
    pushMatrix();
    translate(width/2 + pos.x, height/2 - 20 + pos.y, pos.z);
    noStroke();
    float pct = lifespan / maxLife;
    fill(255, 140 * pct, 20, pct * 200);
    ellipse(0, 0, size * pct, size * pct);
    popMatrix();
  }

  boolean isDead() { return lifespan <= 0; }
}

// -------------------------------------------------------------
// SERIAL PARSER & HUD
// -------------------------------------------------------------
void serialEvent(Serial port) {
  try {
    String inString = port.readStringUntil('\n');
    if (inString != null) {
      inString = trim(inString);
      String[] data = split(inString, ',');
      if (data.length == 2) {
        targetRoll  = float(data[0]);
        targetPitch = float(data[1]);
      }
    }
  } catch (Exception e) {
    // Ignore malformed frame drops
  }
}

void drawHUD() {
  camera();
  hint(DISABLE_DEPTH_TEST);

  // Status Box
  fill(15, 20, 30, 200);
  stroke(40, 50, 70);
  rect(15, 15, 240, 95, 8);

  fill(255);
  textSize(14);
  text("TELEMETRY MONITOR", 30, 38);

  textSize(13);
  fill(currentRoll >= 0 ? color(100, 230, 120) : color(255, 100, 100));
  text("ROLL:  " + nf(currentRoll, 0, 2) + "°", 30, 62);

  fill(currentPitch >= 0 ? color(100, 230, 120) : color(255, 100, 100));
  text("PITCH: " + nf(currentPitch, 0, 2) + "°", 30, 82);

  // Connection Indicator
  fill(serialConnected ? color(50, 220, 100) : color(230, 50, 50));
  noStroke();
  ellipse(230, 34, 10, 10);

  hint(ENABLE_DEPTH_TEST);
}
