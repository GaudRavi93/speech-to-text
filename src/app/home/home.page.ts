import { Component, OnInit, OnDestroy, signal } from '@angular/core';
import SpeechToText, { Language, DownloadedModel, RecognitionResult, DownloadProgress } from 'src/speech-to-text.plugin';
import { 
  IonHeader, 
  IonToolbar, 
  IonTitle, 
  IonContent, 
  IonButton, 
  IonList, 
  IonItem, 
  IonLabel, 
  IonProgressBar,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardTitle,
  IonChip,
  IonIcon
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { mic, micOff, download, globe, checkmarkCircle, alertCircle } from 'ionicons/icons';

@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
  imports: [
    IonHeader, 
    IonToolbar, 
    IonTitle, 
    IonContent, 
    IonButton, 
    IonList, 
    IonItem, 
    IonLabel, 
    IonProgressBar,
    IonCard,
    IonCardContent,
    IonCardHeader,
    IonCardTitle,
    IonChip,
    IonIcon
  ],
})
export class HomePage implements OnInit, OnDestroy {
  isRecording = signal(false);
  recognitionText = signal('');
  downloadProgress = signal(0);
  downloadMessage = signal('');
  isDownloading = signal(false);
  selectedLanguage = signal('en-us');
  supportedLanguages = signal<Language[]>([]);
  downloadedModels = signal<DownloadedModel[]>([]);
  
  private downloadListener: any;
  private recognitionListener: any;

  constructor() {
    addIcons({ mic, micOff, download, globe, checkmarkCircle, alertCircle });
  }

  async ngOnInit() {
    await this.loadSupportedLanguages();
    await this.loadDownloadedModels();
    this.setupListeners();
  }

  ngOnDestroy() {
    if (this.downloadListener) {
      this.downloadListener.remove();
    }
    if (this.recognitionListener) {
      this.recognitionListener.remove();
    }
  }

  private setupListeners() {
    // Listen for download progress
    this.downloadListener = SpeechToText.addListener('downloadProgress', (progress: DownloadProgress) => {
      console.log("progress : " + JSON.stringify(progress));
      
      this.downloadProgress.set(progress.progress);
      this.downloadMessage.set(progress.message);
    });

    // Listen for recognition results
    this.recognitionListener = SpeechToText.addListener('recognitionResult', (result: RecognitionResult) => {
      console.log("result : " + JSON.stringify(result));
      
      if (result.isFinal) {
        this.recognitionText.set(result.text);
      } else {
        // Show partial results in real-time
        this.recognitionText.set(result.text + '...');
      }
    });
  }

  async loadSupportedLanguages() {
    try {
      const result = await SpeechToText.getSupportedLanguages();
      this.supportedLanguages.set(result.languages);
    } catch (error) {
      console.error('Error loading supported languages:', error);
    }
  }

  async loadDownloadedModels() {
    try {
      const result = await SpeechToText.getDownloadedLanguageModels();
      this.downloadedModels.set(result.models);
    } catch (error) {
      console.error('Error loading downloaded models:', error);
    }
  }

  async downloadModel(language: string) {
    this.isDownloading.set(true);
    this.downloadProgress.set(0);
    this.downloadMessage.set('Starting download...');
    
    try {
      const result = await SpeechToText.downloadLanguageModel({ language });
      console.log('Model downloaded:', result);
      await this.loadDownloadedModels(); // Refresh the list
    } catch (error) {
      console.error('Error downloading model:', error);
    } finally {
      this.isDownloading.set(false);
    }
  }

  async startRecognition() {
    if (this.isRecording()) return;
    
    try {
      await SpeechToText.startRecognition({ language: this.selectedLanguage() });
      this.isRecording.set(true);
      this.recognitionText.set('Listening...');
    } catch (error) {
      console.error('Error starting recognition:', error);
    }
  }

  async stopRecognition() {
    if (!this.isRecording()) return;
    
    try {
      await SpeechToText.stopRecognition();
      this.isRecording.set(false);
    } catch (error) {
      console.error('Error stopping recognition:', error);
    }
  }

  isModelDownloaded(languageCode: string): boolean {
    return this.downloadedModels().some(model => model.language === languageCode);
  }

  getLanguageName(code: string): string {
    const language = this.supportedLanguages().find(lang => lang.code === code);
    return language ? language.name : code;
  }

  formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }
}
