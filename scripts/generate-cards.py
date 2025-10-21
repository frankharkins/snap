"""
Script to generate images for card faces.
Requires pillow == 11.3.0
"""

import math
from pathlib import Path
from PIL import Image, ImageFont, ImageDraw, ImageOps, ImageChops

OUTPUT_PATH = Path("frontend/images/faces/")

RED = "#a63d40"
BLACK = "#000"


def rotate(coords: tuple[int, int], angle: float) -> tuple[int, int]:
    x, y = coords
    return (
        round(x*math.cos(angle) - y*math.sin(angle)),
        round(x*math.sin(angle) + y*math.cos(angle))
    )

class Icon:
    def __init__(self, coords):
        self.coords = coords
    def render(self, position=(0,0), scale=1, rotation=0.0):
        scaled = [(x*scale, y*scale) for x,y in self.coords]
        rotated = [rotate(coord, rotation) for coord in scaled]
        transformed = [(x+position[0], y+position[1]) for x,y in rotated]
        return transformed

def color_and_icon(suit: str):
    """
    Get suit color and icon. I hand-drew the icons and copied the coordinates.
    """
    if suit == "hearts":
        return RED, Icon([(2,0), (0,2), (0,5), (6,12), (12, 5), (12, 2), (10, 0), (8, 0), (6, 3), (2,0)])
    if suit == "spades":
        return BLACK, Icon([(6,0),(5,1),(0,5),(0,7),(2,9),(3,9),(4,8),(6,8),(6,10),(3,12),(9,12), (6,10), (6,8), (8,8), (9,9), (10,9), (12,7), (12,5), (7,1), (6,0)])
    if suit == "diamonds":
        return RED, Icon([(6,0), (0,6), (6,12), (12,6), (6,0)])
    if suit == "clubs":
        return BLACK, Icon([
          (7,0),(5,0),(3,2),(3,3),(5,5),(4,7),(3,6),(2,6),(0,8),(0,10),(2,12),(3,12),(5,10),(6,10),(6,12),
          (6,12),(6,10),(7,10),(9,12),(10,12),(12,10),(12,8),(10,6),(9,6),(8,7),(7,5),(9,3),(9,2),
          (7,0),
        ])

def center_layout(number: str | int) -> tuple[float, list[tuple[int, int]]]:
    """
    Get layout for icons on a numbered card
    """
    if number == "A":
        return 2, [(21, 31)]
    if number == 2:
        return .75, [(29, 30), (29, 50)]
    if number == 3:
        return .75, [(29, 23), (29, 38), (29, 53)]
    if number == 4:
        return .75, [(19, 30), (19, 50), (37, 30), (37, 50)]
    if number == 5:
        return .75, [(28, 38), (19, 26), (19, 51), (37, 26), (37, 51)]
    if number == 6:
        return .7, [(22, 25), (22, 38), (22, 51), (35, 25), (35, 38), (35, 51)]
    if number == 7:
        return .7, [(29, 34), (19, 24), (19, 44), (37, 24), (37, 44), (19, 56), (37, 56)]
    if number == 8:
        return .7, [(28, 31), (28, 50), (19, 22), (19, 40), (37, 22), (37, 40), (19, 58), (37, 58)]
    if number == 9:
        return .6, [(28, 40), (19, 22), (37, 22), (19, 32), (19, 47), (37, 32), (37, 47), (19, 58), (37, 58)]
    if number == 10:
        return .55, [(28, 29), (19, 23), (19, 36), (37, 23), (37, 36), (28, 53), (19, 46), (19, 59), (37, 46), (37, 59)]
    raise ValueError(f"Invalid card value '{number}'")

def render_card(suit: str, value: str | int):
    with Image.open("scripts/images/blank-card.bmp") as card:
        font = ImageFont.truetype(".bin/dm-sans.ttf", size=14)
        draw = ImageDraw.Draw(card)
        color, icon = color_and_icon(suit)
        draw.fontmode = "1"

        # draw value and icon in corner
        draw.text((3,2), str(value), fill=color, font=font)
        icon_y_offset = 19 if value == 10 else 15 if value == "Q" else 13
        draw.polygon(icon.render((icon_y_offset,6), 0.75), fill=color)

        # mirror number and icon
        mirror = ImageOps.flip(ImageOps.mirror(card))
        card = ImageChops.multiply(card, mirror)

        # place icons or face image in middle
        if value in ["J","Q","K"]:
            filename = {
                "J": "jack", "Q": "queen", "K": "king"
                }[value]
            with Image.open(f"scripts/images/{filename}.bmp") as face:
                face = ImageChops.add(
                    Image.new("RGBA", (63,88), color=color),
                    face
                )
                card = ImageChops.multiply(card, face)
                draw = ImageDraw.Draw(card)
                if value == "J":
                    draw.line(icon.render((10, 30), rotation=-0.785), fill=color, width=1)
                    draw.line(icon.render((52, 60), rotation=2.356), fill=color, width=1)
                elif value == "Q":
                    draw.line(icon.render((33, 31), scale=0.6), fill=color, width=1)
                    draw.line(icon.render((29, 56), scale=0.6, rotation=3.1415), fill=color, width=1)
                else:
                    draw.line(icon.render((36, 4), scale=0.4), fill=color, width=1)
                    draw.line(icon.render((26, 83), scale=0.4, rotation=3.1415), fill=color, width=1)

        else:
            size, positions = center_layout(value)
            draw = ImageDraw.Draw(card)
            for coord in positions:
                draw.polygon(icon.render(coord, size), fill=color)

        return card

if __name__ == "__main__":
    OUTPUT_PATH.mkdir(exist_ok=True, parents=True)
    for suit in ["clubs", "spades", "hearts", "diamonds"]:
        for value in ["A","J","K","Q"] + list(range(2,11)):
            filename = f"{value}-{suit}.png"
            render_card(suit, value).save(OUTPUT_PATH / filename, optimize=True)
            # print(f'<link rel="prefetch" href="/images/faces/{filename}" />')
