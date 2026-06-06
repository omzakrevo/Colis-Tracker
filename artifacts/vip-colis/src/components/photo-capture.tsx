import { useRef, useState, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Camera, Upload, X, RefreshCw } from "lucide-react";

interface PhotoCaptureProps {
  onChange: (dataUrl: string | null) => void;
  value?: string | null;
}

const MAX_WIDTH = 1024;
const QUALITY = 0.72;

function compressImage(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      URL.revokeObjectURL(url);
      const scale = img.width > MAX_WIDTH ? MAX_WIDTH / img.width : 1;
      const w = Math.round(img.width * scale);
      const h = Math.round(img.height * scale);
      const canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext("2d")!;
      ctx.drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL("image/jpeg", QUALITY));
    };
    img.onerror = reject;
    img.src = url;
  });
}

export function PhotoCapture({ onChange, value }: PhotoCaptureProps) {
  const fileRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const [loading, setLoading] = useState(false);

  const handleFile = useCallback(async (file: File | undefined) => {
    if (!file) return;
    setLoading(true);
    try {
      const compressed = await compressImage(file);
      onChange(compressed);
    } finally {
      setLoading(false);
    }
  }, [onChange]);

  const clear = () => {
    onChange(null);
    if (fileRef.current) fileRef.current.value = "";
    if (cameraRef.current) cameraRef.current.value = "";
  };

  if (value) {
    return (
      <div className="space-y-2">
        <div className="relative rounded-xl overflow-hidden border border-border bg-muted">
          <img
            src={value}
            alt="Photo du colis"
            className="w-full object-contain max-h-56"
          />
          <button
            type="button"
            onClick={clear}
            className="absolute top-2 right-2 bg-black/60 hover:bg-black/80 text-white rounded-full p-1 transition-colors"
            aria-label="Supprimer la photo"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="h-7 text-xs text-muted-foreground"
          onClick={() => fileRef.current?.click()}
        >
          <RefreshCw className="w-3 h-3 mr-1" /> Changer la photo
        </Button>
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => handleFile(e.target.files?.[0])}
        />
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div
        className="rounded-xl border-2 border-dashed border-border bg-muted/30 flex flex-col items-center justify-center gap-3 py-8 cursor-pointer hover:bg-muted/60 transition-colors"
        onClick={() => fileRef.current?.click()}
      >
        {loading ? (
          <div className="flex flex-col items-center gap-2 text-muted-foreground">
            <RefreshCw className="w-6 h-6 animate-spin" />
            <span className="text-sm">Compression…</span>
          </div>
        ) : (
          <>
            <Upload className="w-8 h-8 text-muted-foreground" />
            <p className="text-sm text-muted-foreground text-center">
              Cliquez pour choisir une image
              <br />
              <span className="text-xs">ou utilisez l'appareil photo ci-dessous</span>
            </p>
          </>
        )}
      </div>

      <div className="flex gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="flex-1"
          onClick={() => fileRef.current?.click()}
          disabled={loading}
        >
          <Upload className="w-4 h-4 mr-2" /> Galerie / Fichier
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="flex-1"
          onClick={() => cameraRef.current?.click()}
          disabled={loading}
        >
          <Camera className="w-4 h-4 mr-2" /> Appareil photo
        </Button>
      </div>

      {/* file picker — any image */}
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => handleFile(e.target.files?.[0])}
      />
      {/* camera capture — rear camera on mobile */}
      <input
        ref={cameraRef}
        type="file"
        accept="image/*"
        capture="environment"
        className="hidden"
        onChange={(e) => handleFile(e.target.files?.[0])}
      />
    </div>
  );
}
