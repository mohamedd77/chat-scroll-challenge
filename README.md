# Chat Auto-Scroll Challenge

## Setup

1. Get a free Gemini API key from [ai.google.dev](https://ai.google.dev)
2. Run `flutter pub get`
3. Run `flutter run` (web, macOS, or any platform)
4. Enter your API key and start chatting

## The Problem

This app uses [flutter_chat_ui](https://github.com/flyerhq/flutter_chat_ui) to display a streaming chat with Google Gemini. When you send a message, the AI response streams in token by token.

**Try it:** Send multiple messages (e.g. _"Write a detailed essay about the history of the internet"_) and notice the scroll UX issues as the responses stream in.

## Your Task

Compare the scroll behavior between this app and the reference implementation: https://iman-admin.github.io/chat-scroll-demo/

Identify the UX issues and fix them. Your solution must match the scroll behavior of the reference implementation.

**Test it thoroughly before you start coding.** Pay attention to every detail of how auto-scroll engages, disengages, and resumes. Your solution will be scored primarily on how closely it matches this behavior.

You are free to use any AI tools you'd like. What matters is the end result.

## How to Submit

1. Clone this repo into a **private** repository on your own GitHub account.
2. Implement your solution.
3. Deploy your solution to the web (GitHub Pages, Firebase Hosting, or any hosting).
4. Update this README with:
   - A list of the UX issues you identified and fixed.
   - Your deployed URL.
   - A screen recording demonstrating each fix.
6. Add **IMan-admin** as a collaborator to your private repo.
7. Send us the link to your repo.

## Evaluation Criteria

- Does it auto-scroll during streaming?
- Does manual scroll-away pause auto-scroll?
- Does returning to bottom resume auto-scroll?
- Is the code clean, testable, and well-separated?
- Are edge cases handled?
