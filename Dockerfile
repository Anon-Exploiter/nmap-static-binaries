FROM andrewd/musl-cross

# Build
ADD build.sh /build/build.sh

# Runs build.sh
ENTRYPOINT [ "/build/build.sh" ] 
