// Barcode Scanner functionality using QuaggaJS

// Import QuaggaJS and expose it globally
import Quagga from "../vendor/quagga.min.js"

// Make sure Quagga is available globally
if (typeof window !== 'undefined') {
  window.Quagga = Quagga;
}

class BarcodeScanner {
  constructor() {
    this.isScanning = false;
    this.onDetectedCallback = null;
    this.onErrorCallback = null;
  }

  // Initialize the scanner with a target element
  init(targetSelector, options = {}) {
    // Use the imported Quagga or global window.Quagga
    const QuaggaInstance = Quagga || window.Quagga;
    
    if (typeof QuaggaInstance === 'undefined') {
      throw new Error('QuaggaJS is not loaded. Please ensure the script is included.');
    }

    const defaultOptions = {
      inputStream: {
        type: "LiveStream",
        target: document.querySelector(targetSelector),
        constraints: {
          width: { min: 640, ideal: 1280, max: 1920 },
          height: { min: 480, ideal: 720, max: 1080 },
          facingMode: "environment" // Use back camera on mobile
        }
      },
      locator: {
        patchSize: "medium",
        halfSample: true
      },
      numOfWorkers: 0, // Disable web workers to prevent disconnection errors
      frequency: 10, // Check frames per second
      decoder: {
        readers: [
          "ean_reader", // For ISBN (EAN-13) - most common for books
          "ean_8_reader", // For EAN-8
          "code_128_reader", // For Code 128
          "code_39_reader", // For Code 39
        ],
        multiple: false // Stop after first successful read
      },
      locate: true,
      debug: {
        drawBoundingBox: false,
        showFrequency: false,
        drawScanline: false,
        showPattern: false
      }
    };

    const config = { ...defaultOptions, ...options };

    return new Promise((resolve, reject) => {
      QuaggaInstance.init(config, (err) => {
        if (err) {
          console.error("QuaggaJS initialization failed:", err);
          if (this.onErrorCallback) this.onErrorCallback(err);
          reject(err);
        } else {
          console.log("QuaggaJS initialized successfully");
          this.setupEventListeners(QuaggaInstance);
          resolve();
        }
      });
    });
  }

  // Setup event listeners for barcode detection
  setupEventListeners(QuaggaInstance) {
    QuaggaInstance.onDetected((result) => {
      const code = result.codeResult.code;
      const format = result.codeResult.format;
      
      console.log(`Barcode detected: ${code} (${format})`);
      
      // Validate barcode (basic length check for ISBN)
      if (this.isValidISBN(code)) {
        if (this.onDetectedCallback) {
          this.onDetectedCallback(code, format);
        }
      }
    });

    // Listen for processing errors
    QuaggaInstance.onProcessed((result) => {
      const drawingCtx = QuaggaInstance.canvas.ctx.overlay;
      const drawingCanvas = QuaggaInstance.canvas.dom.overlay;
      
      if (result) {
        // Draw bounding box around detected codes
        if (result.boxes) {
          drawingCtx.clearRect(0, 0, parseInt(drawingCanvas.getAttribute("width")), parseInt(drawingCanvas.getAttribute("height")));
          result.boxes.filter(box => box !== result.box).forEach(box => {
            QuaggaInstance.ImageDebug.drawPath(box, {x: 0, y: 1}, drawingCtx, {color: "green", lineWidth: 2});
          });
        }

        if (result.box) {
          QuaggaInstance.ImageDebug.drawPath(result.box, {x: 0, y: 1}, drawingCtx, {color: "#00F", lineWidth: 2});
        }

        if (result.codeResult && result.codeResult.code) {
          QuaggaInstance.ImageDebug.drawPath(result.line, {x: 'x', y: 'y'}, drawingCtx, {color: 'red', lineWidth: 3});
        }
      }
    });
    
    // Store the instance for later use
    this.quaggaInstance = QuaggaInstance;
  }

  // Start scanning
  start() {
    if (!this.isScanning && this.quaggaInstance) {
      this.quaggaInstance.start();
      this.isScanning = true;
      console.log("Barcode scanning started");
    }
  }

  // Stop scanning
  stop() {
    if (this.isScanning && this.quaggaInstance) {
      try {
        this.quaggaInstance.stop();
        // Give a small delay before cleanup
        setTimeout(() => {
          if (this.quaggaInstance && this.quaggaInstance.offDetected) {
            this.quaggaInstance.offDetected();
            this.quaggaInstance.offProcessed();
          }
        }, 100);
      } catch (error) {
        console.warn("Error stopping scanner:", error);
      }
      this.isScanning = false;
      console.log("Barcode scanning stopped");
    }
  }

  // Set callback for when barcode is detected
  onDetected(callback) {
    this.onDetectedCallback = callback;
  }

  // Set callback for errors
  onError(callback) {
    this.onErrorCallback = callback;
  }

  // Basic ISBN validation
  isValidISBN(code) {
    // Remove any hyphens or spaces
    const cleanCode = code.replace(/[-\s]/g, '');
    
    // Check if it's 10 or 13 digits
    if (cleanCode.length === 10 || cleanCode.length === 13) {
      return /^[0-9]{9,12}[0-9X]?$/.test(cleanCode);
    }
    
    return false;
  }

  // Check if camera is supported
  static isCameraSupported() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  }
}

// Export for use in Phoenix templates
window.BarcodeScanner = BarcodeScanner;

export default BarcodeScanner;