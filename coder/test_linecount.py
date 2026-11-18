from linecount import line_count

assert line_count("a\nb") == 2
assert line_count("") == 0
assert line_count("x") == 1

print("All tests passed")
