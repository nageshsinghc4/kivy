#!/usr/bin/env sh

# ImageMagickFormat:extension
FMT_OPAQUE="TIFF:tiff BMP:bmp BMP3:bmp PNG:png GIF87:gif CUR:cur"
FMT_BINARY="BMP:bmp GIF:gif PNG8:png PNG24:png PNG48:png ICO:ico"
FMT_ALPHA="PNG32:png PNG64:png TGA:tga SGI:sgi DPX:dpx"

# FIXME: Magick output is not completely predictable. Some images
# become gray+alpha, some palette, some bitonal, and it's not obvious
# how/if this can be controlled better
#FMT_BITONAL=""
FMT_GRAY_OPAQUE=""
FMT_GRAY_BINARY="PNG8:png"
FMT_GRAY_ALPHA="PNG:png"

# Pixel values used for different tests
PIX_alpha="twxrgbcyp0123456789ABCDEF"
PIX_opaque="wxrgbcyp0123456789ABCDEF"
PIX_binary="twrgbcyp123456789ABCDEF"
PIX_gray_opaque="0123456789ABCDEF"
PIX_gray_binary="t123456789ABCDEF"
PIX_gray_alpha="t0123456789ABCDEF"


usage() { cat <<EOM
Usage: $0 <target-directory>

Creates test images in many formats using ImageMagick 'convert'
utility. The pixel values are encoded in the filename, so they
can be reconstructed and verified.

v0_<W>x<H>_<pattern>_<alpha>_<format>_<info>.<extension>

  Example: "v0_3x1_rgb_FF_PNG24_OPAQUE.png" is a 3x1 image with
  red, green and blue pixels. Alpha is FF, the ImageMagick
  format is PNG24. <info> is used to distinguish tests that
  use the same pattern but differ in other parameters
  (currently _OPAQUE, _BINARY and _ALPHA)

  The leading 'v0_' indicates version 0 of the test protocol,
  which is defined by this implementation. All v0 images are
  either a single row or single column of pixels with values:

Pattern legend:

  w: White  (#fff)    x: Black (#000)** t: Transp (#0000)**
  r: Red    (#f00)    g: Green (#0f0)   b: Blue   (#00f)
  y: Yellow (#ff0)    c: Cyan  (#0ff)   p: Purple (#f0f)

  0-9 A-F (uppercase) represent pixels with the given value
          in all nibbles, so 3 = #333333, A = #AAAAA. Alpha
          is global and not affected by the pixel values.

  ** 't' cannot be combined with 'x' or '0' in the same pattern
     for testing binary transparency (all black pixels become
     transparent for some formats, causing tests to fail).

EOM
}

# Outputs command line arguments for convert to draw pixels from the
# specifed pattern in the specified direction. It is always 1 in w or h.
draw_pattern() {
    pattern=$1
    direction="${2:-x}"
    alpha=${3:-FF}
    pos=0
    for char in $(echo $pattern | fold -w1); do
        case $char in
            t) fill="#00000000" ;;
            w) fill="#FFFFFF${alpha}" ;;
            x) fill="#000000${alpha}" ;;
            r) fill="#FF0000${alpha}" ;;
            g) fill="#00FF00${alpha}" ;;
            b) fill="#0000FF${alpha}" ;;
            y) fill="#FFFF00${alpha}" ;;
            c) fill="#00FFFF${alpha}" ;;
            p) fill="#FF00FF${alpha}" ;;
            0|1|2|3|4|5|6|7|8|9|A|B|C|D|E|F)
                fill="#${char}${char}${char}${char}${char}${char}${alpha}"
            ;;
            *) (>&2 echo "Error: Invalid pattern char: $char"); exit 100 ;;
        esac
        case $direction in
            y|height) echo -n "-draw 'fill $fill color 0, $pos point' " ;;
            x|width)  echo -n "-draw 'fill $fill color $pos, 0 point' " ;;
        esac
        pos=$((pos+1))
    done
}

# Creates 1xN and Nx1 test images from the given pattern, in the given
# format. Only use alpha != FF if you are actually testing alpha.
make_images() {
    pattern=$1
    len=${#pattern}

    if [ -z $pattern ] || [ -z $TESTFMT ] || [ -z $TESTEXT ]; then
        (>&2 echo "make_images() missing required arguments/environment")
        exit 101
    fi
    if [ ${#TESTALPHA} != 2 ]; then
        (>&2 echo "make_images() invalid TESTALPHA: $TESTALPHA")
        exit 102
    fi

    # Nx1
    ending="${TESTALPHA}_${TESTFMT}_${TESTNAME}.${TESTEXT}"
    outfile="v0_${len}x1_${pattern}_${ending}"
    eval convert -size ${len}x1 xc:none -quality 100% $TESTARGS \
        $(draw_pattern "$pattern" "x" "$alpha") \
        ${convert_args} \
        "${TESTFMT}:$destdir/$outfile"

    # 1xN - don't create duplicates for single pixel
    if [ $len -ne 1 ]; then
        outfile="v0_1x${len}_${pattern}_${ending}"
        eval convert -size 1x${len} xc:none -quality 100% $TESTARGS \
            $(draw_pattern "$pattern" "y" "$alpha") \
            "${TESTFMT}:$destdir/$outfile"
    fi
}

# Make a random pattern from given characters $1 at length $2
# FIXME: portability?
mkpattern() {
    < /dev/urandom LC_ALL=C tr -dc "$1" | head -c $2
}

# Makes simple permutations and random patterns, optionally with
# prefix and postfix (args are pattern, prefix, postfix)
permutepattern() {
    if [ -z "$1" ]; then
        (>&2 echo "permutepattern() missing required argument")
        exit 200
    fi

    # Individual pixel values + poor permutation FIXME
    for char in $(echo $1 | fold -w1); do
        echo -n "$2${char}$3 "
        if [ ! -z $p1 ]; then echo -n "$2${char}${p1}$3 "; fi
# Uncomment for more data
#        if [ ! -z $p2 ]; then echo -n "$2${char}${p1}${p2}$3 "; fi
#        if [ ! -z $p3 ]; then echo -n "$2${char}${p1}${p2}${p3}$3 "; fi
#        if [ ! -z $p4 ]; then echo -n "$2${char}${p1}${p2}${p3}${p4}$3 "; fi
        p4=$p3 ; p3=$p2 ; p2=$p1 ; p1=$char
    done

    # Random
    for i in $(seq 3 9) $(seq 14 17) $(seq 31 33); do
        echo -n "$2$(mkpattern "$1" "$i")$3 "
    done
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "Usage: $0 <target-directory>  (or -h for help)"
    exit 1
fi

case $1 in
    -h|--help) usage; exit 1 ;;
esac

if [ ! -d "$1" ]; then
    (>&2 echo "Error: Destination directory '$1' does not exist")
    exit 2
elif [ ! -w "$1" ]; then
    (>&2 echo "Error: Destination directory '$1' not writeable")
    exit 2
fi
destdir=$(cd "$1"; echo $(pwd))

if [ ! -x "$(command -v convert)" ]; then
    (2>&1 echo "Required ImageMagick 'convert' not found in path")
    exit 3
fi


# - Opaque patterns only include solid colors, alpha is fixed at FF
# - Binary patterns MUST include 't' pixels and MUST NOT include 'x' or 'F'
# - Alpha can combine any pixel value and use alpha != FF
PAT_opaque=$(permutepattern "$PIX_opaque")
PAT_binary=$(permutepattern "$PIX_binary" "t")
PAT_alpha="${PAT_binary} $(permutepattern "$PIX_alpha")"

# Grayscale patterns use only grayscale pixel values + 't' and alpha,
# ie #000 #111 #222 .. #EEE #FFF (0 1 2 .. E F in patterns)
PAT_gray_opaque=$(permutepattern "$PIX_gray_opaque")
PAT_gray_binary=$(permutepattern "$PIX_gray_binary" "t")
PAT_gray_alpha="${PAT_gray_binary} $(permutepattern "$PIX_gray_alpha")"

start() {
    TESTNAME="$1"
    TESTARGS="$2"
    TESTALPHA="FF"
    TESTFMT=""
    TESTEXT=""
}

inform() {
    echo "[${TESTNAME}] Creating ${TESTFMT} (.${TESTEXT}) test images..."
}

# OPAQUE / GRAY_OPAQUE
start "OPAQUE" "-alpha off"
for rawfmt in $FMT_OPAQUE $FMT_BINARY $FMT_ALPHA; do
    TESTFMT=${rawfmt%:*}; TESTEXT=${rawfmt#*:}; inform
    for pat in $PAT_opaque; do
        make_images "$pat"
    done
done

start "GRAY_OPAQUE" "-alpha off -colorspace Gray"
for rawfmt in $FMT_GRAY_OPAQUE $FMT_GRAY_BINARY $FMT_GRAY_ALPHA; do
    TESTFMT=${rawfmt%:*}; TESTEXT=${rawfmt#*:}; inform
    for pat in $PAT_gray_opaque; do
        make_images "$pat"
    done
done

# BINARY / GRAY_BINARY
start "BINARY" "-alpha on"
for rawfmt in $FMT_BINARY $FMT_ALPHA; do
    TESTFMT=${rawfmt%:*}; TESTEXT=${rawfmt#*:}; inform
    for pat in $PAT_binary; do
        make_images "$pat"
    done
done

start "GRAY_BINARY" "-alpha on -colorspace Gray"
for rawfmt in $FMT_GRAY_BINARY $FMT_GRAY_ALPHA; do
    TESTFMT=${rawfmt%:*}; TESTEXT=${rawfmt#*:}; inform
    for pat in $PAT_gray_binary; do
        make_images "$pat"
    done
done

# ALPHA / GRAY_ALPHA
start "ALPHA" "-alpha on"
for rawfmt in $FMT_ALPHA; do
    TESTFMT=${rawfmt%:*}; TESTEXT=${rawfmt#*:}; inform
    for alpha in 7F F0; do
        TESTALPHA=$alpha
        for pat in $PAT_alpha; do
            make_images "$pat"
        done
    done
done

start "GRAY_ALPHA" "-alpha on -colorspace Gray"
for rawfmt in $FMT_GRAY_ALPHA; do
    TESTFMT=${rawfmt%:*}; TESTEXT=${rawfmt#*:}; inform
    for alpha in 7F F0; do
        TESTALPHA=$alpha
        for pat in $PAT_gray_alpha; do
            make_images "$pat"
        done
    done
done
