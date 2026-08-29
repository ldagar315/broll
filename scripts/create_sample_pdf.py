from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
)


OUTPUT = Path(__file__).resolve().parents[1] / "output" / "pdf" / "random_story.pdf"


CHAPTERS = [
    (
        "Chapter 1: The Unlit Beacon",
        [
            "Mara Vale arrived at Lake Merrow just before the first snow. The village road ended at a black pier, and beyond it the water held the color of old glass.",
            "At the end of the pier stood a lighthouse with no lamp. Its windows were dark, its door was chained, and a brass plate said that the beacon had been retired forty years earlier.",
            "Mara had come to catalogue the abandoned station for the city archive. She carried a notebook, a thermos, and a letter written in her grandmother's careful hand.",
            "The letter contained only one instruction: when the lake begins to ring, light the lantern before the second bell.",
            "She thought it was a family joke until the ice beneath the pier made a clear, ringing sound. The note in her pocket seemed to grow heavier.",
            "A small rowboat knocked against the posts. Inside it lay a wooden key, a coil of blue rope, and a tin box marked with the same crescent shape as the lighthouse door.",
        ],
    ),
    (
        "Chapter 2: The House Beneath the Water",
        [
            "The key opened the lighthouse without turning. The chain fell away as if it had been waiting, and the door breathed out a smell of rain, dust, and something green.",
            "The ground floor was empty except for a spiral staircase. Each step had a name carved into it, and the names belonged to people who had disappeared from the village records.",
            "Mara climbed until she reached a room with a round window. Through the glass she could see a second house standing on the lake floor, its chimney pointing toward the surface.",
            "The tin box contained a map drawn on thin copper. A red line travelled from the lighthouse to the submerged house, then stopped at a blank circle beneath the deepest part of the lake.",
            "When Mara touched the map, the lake rang again. This time the sound came from below her feet, and a pale light moved through the water like a lantern carried by a slow walker.",
            "She tied the blue rope around the stair rail and opened the trapdoor beneath the window. Cold air rose from the dark, carrying the scent of pine needles from a forest that no longer existed.",
        ],
    ),
    (
        "Chapter 3: The Keeper's Promise",
        [
            "The stairway below the lighthouse did not lead down. It led sideways, through a corridor where the walls were made of clear water and small fish watched Mara pass.",
            "At the end of the corridor she found a room filled with lanterns. Every lantern held a different memory: a wedding under summer rain, a child running through wheat, a dog asleep beside a stove.",
            "An old man sat beside the largest lantern. His coat was stitched with silver thread, and his face looked exactly like the portrait of Mara's grandfather in the village archive.",
            "He told her that the beacon had never guided ships. It guided memories back to the people who had lost them, but the light required a keeper willing to remember everything.",
            "Mara asked why her grandmother had sent her. The old man pointed to a dark lantern at the center of the room. Inside it, a little girl was waiting beside a summer road.",
            "The girl was Mara's grandmother. She had promised the lake that one day her granddaughter would come, not to break the promise, but to choose whether it should continue.",
        ],
    ),
    (
        "Chapter 4: The Second Bell",
        [
            "Above the water, the first bell began to ring. The sound travelled through the corridor and shook dust from the lantern shelves.",
            "Mara understood that the blank circle on the copper map was not a place. It was a choice. If she lit the beacon, every memory in the room would return to the village, along with the grief attached to it.",
            "If she left the lantern dark, the memories would remain safe beneath the lake, and the village would continue its quiet forgetting.",
            "She thought of the empty places in her grandmother's stories, the names carved into the stairs, and the feeling of being homesick for a house she had never seen.",
            "Then she opened the largest lantern and carried its flame to the old beacon. The light rose through the tower, crossed the frozen lake, and touched every window in the village.",
            "The second bell rang. By morning, people were standing on their doorsteps with tears on their faces and names returning to their lips.",
            "Mara left the lighthouse unlocked. In the notebook she wrote a new instruction for whoever came next: remember gently, and never let the lantern burn alone.",
        ],
    ),
]


def draw_footer(canvas, document):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColorRGB(0.45, 0.45, 0.45)
    canvas.drawCentredString(
        LETTER[0] / 2,
        0.45 * inch,
        f"The Lantern at Lake Merrow - {document.page}",
    )
    canvas.restoreState()


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    styles = getSampleStyleSheet()
    title = ParagraphStyle(
        "StoryTitle",
        parent=styles["Title"],
        alignment=TA_CENTER,
        fontName="Helvetica-Bold",
        fontSize=25,
        leading=31,
        spaceAfter=16,
    )
    author = ParagraphStyle(
        "StoryAuthor",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontName="Helvetica",
        fontSize=12,
        leading=16,
        textColor="#555555",
    )
    chapter = ParagraphStyle(
        "ChapterHeading",
        parent=styles["Heading1"],
        fontName="Helvetica-Bold",
        fontSize=17,
        leading=22,
        spaceAfter=18,
    )
    body = ParagraphStyle(
        "StoryBody",
        parent=styles["BodyText"],
        fontName="Times-Roman",
        fontSize=11.5,
        leading=17,
        spaceAfter=12,
    )

    document = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=LETTER,
        rightMargin=0.85 * inch,
        leftMargin=0.85 * inch,
        topMargin=0.8 * inch,
        bottomMargin=0.75 * inch,
        title="The Lantern at Lake Merrow",
        author="Avery Finch",
    )

    story = [
        Spacer(1, 2.1 * inch),
        Paragraph("The Lantern at Lake Merrow", title),
        Paragraph("A short demonstration story by Avery Finch", author),
        PageBreak(),
    ]
    for chapter_title, paragraphs in CHAPTERS:
        story.append(Paragraph(escape(chapter_title), chapter))
        for paragraph in paragraphs:
            story.append(Paragraph(escape(paragraph), body))
        story.append(PageBreak())

    document.build(story, onFirstPage=draw_footer, onLaterPages=draw_footer)
    print(OUTPUT)


if __name__ == "__main__":
    main()
