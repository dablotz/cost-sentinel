import json

from handler import handler

if __name__ == "__main__":
    with open("events/sample_sns_budget.json") as f:
        event = json.load(f)
    print(handler(event, None))
