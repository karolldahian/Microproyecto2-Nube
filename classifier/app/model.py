import torch
from PIL import Image
from torchvision.models import ResNet18_Weights, resnet18

_weights = ResNet18_Weights.IMAGENET1K_V1
_model = None


def get_model():
    global _model
    if _model is None:
        model = resnet18(weights=_weights)
        model.eval()
        _model = model
    return _model


def predict(image: Image.Image) -> dict:
    model = get_model()
    tensor = _weights.transforms()(image).unsqueeze(0)
    with torch.no_grad():
        logits = model(tensor)
        probabilities = torch.softmax(logits, dim=1)
    class_idx = torch.argmax(probabilities, dim=1).item()
    return {
        "class": _weights.meta["categories"][class_idx],
        "confidence": probabilities[0, class_idx].item(),
    }