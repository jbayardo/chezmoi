import getpass


def char_to_number(input_string):
    # Mapping of letters to numbers
    mapping = {
        "a": "2",
        "b": "2",
        "c": "2",
        "d": "3",
        "e": "3",
        "f": "3",
        "g": "4",
        "h": "4",
        "i": "4",
        "j": "5",
        "k": "5",
        "l": "5",
        "m": "6",
        "n": "6",
        "o": "6",
        "p": "7",
        "q": "7",
        "r": "7",
        "s": "7",
        "t": "8",
        "u": "8",
        "v": "8",
        "w": "9",
        "x": "9",
        "y": "9",
        "z": "9",
        "0": "0",
        "1": "1",
        "2": "2",
        "3": "3",
        "4": "4",
        "5": "5",
        "6": "6",
        "7": "7",
        "8": "8",
        "9": "9",
    }

    # Convert each character in the input string to the corresponding number
    output_numbers = ""
    for char in input_string.lower():
        if char in mapping:
            output_numbers += mapping[char]
        else:
            # Any character not defined in the mapping gets a '*'
            output_numbers += "*"

    return output_numbers


def main():
    input_text = getpass.getpass("Enter a string to convert: ")
    converted = char_to_number(input_text)
    print(f"{converted}")


if __name__ == "__main__":
    main()
