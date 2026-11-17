from slugify import slugify

assert slugify("Hello, World!") == "hello-world"
assert slugify("  A  B ") == "a-b"
assert slugify("---") == ""

print("All tests passed")
