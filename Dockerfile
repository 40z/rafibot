# Hubot needs node to run.
FROM node:19

# Environment variables:
# Forces non-interactive mode for apt commands.
ENV DEBIAN_FRONTEND="noninteractive"
# The clever name you came up with earlier.
ENV HUBOT_NAME="rafibot"
# The person to contact if Hubot breaks.
ENV HUBOT_OWNER="gitgud@40z.club"
# A description for the bot if you want one. This is more
# important if you have multiple bots.
ENV HUBOT_DESCRIPTION="FOURDEEEZZ!!!"

# Create a user to run Hubot as.
RUN useradd hubot -m
# Copy this repository to the user's home directory.
COPY . /home/hubot
# And make sure that the files have the right owner and group.
RUN chown -R hubot:hubot /home/hubot

# Use the new user for running commands.
USER hubot
# Set the working directory to be the user's home directory.
WORKDIR /home/hubot
# Install dependencies.
RUN npm install

# Set a default command to run Hubot!
EXPOSE 8080
CMD ./bin/hubot -n $HUBOT_NAME -a discord
