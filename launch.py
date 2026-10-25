import os
import sys

# Set up base directories
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from desktop.main import main

if __name__ == "__main__":
    main()
