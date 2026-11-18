def line_count(text):
    if text == "":
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)
