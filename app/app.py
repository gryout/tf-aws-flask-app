from flask import Flask, request
import logging
import os

app = Flask(__name__)

app.logger.setLevel(logging.INFO)

@app.route('/')
def hello():
    app.logger.info(request.headers)
    return os.environ['TEST']

if __name__ == "__main__":
    app.run(debug=True)