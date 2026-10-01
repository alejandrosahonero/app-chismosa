#!/usr/bin/env python3
"""Builds supabase/seed/common_words.txt: the common-word shield of 0016.

The fuzzy name and insult filters (supabase/migrations/0016) ignore any word
in public.common_words. This script fills it with the 50,000 most frequent
Spanish and English words (hermitdave/FrequencyWords, OpenSubtitles 2018),
minus the words the filters must still catch: first names and their spelling
variants, frequent surnames, and insults with their variants. It uses the
same phonetic key as public.word_key(), so keep the two in sync.

    python3 tool/build_common_words.py   # writes supabase/seed/common_words.txt

The lists below mirror the database (0011, 0012, 0016). Add a name or an
insult there and here, then rerun this and reload the seed.
"""
import re
import unicodedata
import urllib.request

SOURCE = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/{lang}/{lang}_50k.txt"

NAMES_ES = "adrian,adriana,agustin,agustina,aimar,aitana,alba,alberto,ale,alejandra,alejandro,alex,alfonso,alfredo,alicia,alvaro,amanda,ana,andrea,andres,angela,angelica,antonia,antonio,araceli,ariadna,armando,arturo,aurora,axel,bea,beatriz,benjamin,bernardo,berta,brayan,brenda,bruno,camila,carla,carlitos,carlos,carmen,carolina,catalina,cecilia,cesar,charly,chema,christian,chucho,claudia,conchi,cristian,cristina,dani,daniel,daniela,dario,david,diana,diego,dylan,edu,eduardo,edwin,elena,eliana,elias,elisa,elsa,emilia,emilio,emma,enrique,erick,erik,ernesto,esteban,estefania,eugenia,eva,evelyn,fabian,fabiola,fede,federico,felipe,fer,fernanda,fernando,fran,francisco,freddy,frida,gabi,gabriel,gabriela,gael,gerardo,german,gilberto,gisela,gonzalo,grover,guadalupe,guille,guillermo,gustavo,hector,hugo,ignacio,iker,ines,irene,isaac,isabel,isabela,ismael,ivan,ivonne,izan,jaime,jaume,javi,javier,jazmin,jennifer,jessica,jesus,jhonny,jiahe,jimena,joaquin,jonathan,jordi,jorge,jose,josefina,juan,juana,juanito,juanjo,julia,julian,julio,karen,karina,kevin,kike,laura,leonardo,leticia,liliana,limbert,lorena,lorenzo,lucas,lucho,lucia,luciana,luis,luisa,lupe,lupita,manolo,manu,manuel,marc,marcela,marcelino,marcelo,marco,marcos,mari,maria,mariana,mariano,maribel,marina,mario,marisol,marta,martha,martin,mateo,matias,mauricio,max,maximiliano,mayra,melissa,memo,miguel,miriam,monica,nacho,nando,natalia,nati,nerea,nico,nicolas,noelia,nuria,oliver,olivia,omar,oriol,oscar,pablo,paco,paola,patricia,paty,pau,paula,pedro,pepe,quique,rafa,rafael,ramiro,ramon,raquel,raul,rebeca,regina,renata,ricardo,roberto,rocio,rodrigo,rogelio,rolando,ruben,samuel,sandra,santi,santiago,sara,sarah,sebastian,sergio,silvia,sofia,sonia,susana,tania,tere,teresa,thiago,tomas,toño,unai,valentina,valeria,vanesa,vanessa,veronica,vicente,victor,wendy,wilmer,wilson,ximena,yessica,yolanda,zoe".split(",")
NAMES_EN = "james,john,robert,michael,david,richard,joseph,thomas,charles,christopher,daniel,matthew,anthony,donald,steven,paul,andrew,joshua,kenneth,kevin,brian,george,timothy,ronald,edward,jason,jeffrey,ryan,jacob,gary,nicholas,eric,jonathan,stephen,larry,justin,scott,brandon,benjamin,samuel,gregory,alexander,patrick,dennis,tyler,aaron,jose,adam,nathan,henry,zachary,douglas,peter,kyle,noah,ethan,jeremy,walter,christian,keith,roger,terry,austin,sean,gerald,carl,harold,dylan,arthur,lawrence,jordan,jesse,bryan,joe,logan,albert,willie,alan,eugene,russell,vincent,philip,bobby,johnny,bradley,mary,patricia,jennifer,linda,elizabeth,barbara,susan,jessica,sarah,karen,lisa,nancy,betty,sandra,margaret,ashley,kimberly,emily,donna,michelle,carol,amanda,melissa,deborah,stephanie,dorothy,rebecca,sharon,laura,cynthia,amy,kathleen,angela,shirley,brenda,anna,pamela,nicole,samantha,katherine,emma,helen,christine,debra,rachel,carolyn,janet,maria,catherine,heather,diane,olivia,julie,joyce,victoria,ruth,virginia,lauren,kelly,christina,joan,evelyn,judith,andrea,hannah,megan,cheryl,jacqueline,martha,madison,teresa,gloria,sara,janice,ann,kathryn,abigail,sophia,frances,jean,alice,judy,isabella,julia,denise,amber,doris,marilyn,danielle,beverly,charlotte,natalie,theresa,diana,brittany,kayla,alexis,lori,taylor,mike,jim,tom,bob,dave,steve,chris,matt,tony,josh,ben,sam,nick,alex,jake,luke,liam,mason,lucas,oliver,elijah,aiden,jackson,sebastian,mia,ava,sophie,chloe,zoe,ella,lily,grace,harper,emily,abby,kate,katie,jenny,jen,becky,liz,beth,meg,sue".split(",")
# English names that are everyday words: not names for the filter.
EN_AMBIGUOUS = set("will,mark,bill,rose,grace,hope,faith,joy,may,june,april,dawn,art,pat,sue,don,ray,jack,frank,lily,ruby,amber,jade,summer,autumn,cash,chase,hunter,gene,carol,joyce,victoria,taylor,jean,ann,doris,harper,mason,jordan,austin,eugene,gloria,mike,bob,ben,sam,nick,kate,beth,meg,lily,grace,abby,liz,jim,tom,joe,chris,matt,tony,josh,steve,dave,alex,luke,jake,jenny,becky,katie,jen,virginia,madison".split(","))
BAD_ES = "bastarda,bastardo,bollera,cabron,cabrona,capulla,capullo,chinga,chingada,chingado,cojuda,cojudo,culera,culero,desgraciada,desgraciado,escoria,gilipollas,golfa,guarra,hijueputa,huevon,huevona,imbecil,jotito,joto,malparida,malparido,mamon,mamona,marica,maricon,mariposon,mariquita,mongola,mongolica,mongolico,mongolo,moraco,negrata,panchito,pendeja,pendejo,puta,puto,retrasada,retrasado,sarasa,sidosa,sidoso,subnormal,sudaca,tortillera,travelo,verga,zorra".split(",")
BAD_EN = "faggot,fag,tranny,shemale,retard,retarded,nigger,nigga,chink,spic,wetback,beaner,gook,slut,whore,bitch,cunt,twat,bastard,asshole,motherfucker,dickhead,cocksucker,douchebag,skank".split(",")
SURNAMES = set("garcia,rodriguez,gonzalez,fernandez,lopez,martinez,sanchez,perez,gomez,jimenez,ruiz,hernandez,diaz,alvarez,munoz,romero,alonso,gutierrez,navarro,torres,dominguez,vazquez,ramirez,serrano,molina,morales,suarez,ortega,delgado,castro,ortiz,marin,sanz,nunez,iglesias,medina,garrido,cortes,lozano,guerrero,prieto,mendez,flores,herrera,marquez,cabrera,gallego,calvo,vidal,carrasco,aguilar,caballero,nieto,santana,pascual,herrero,montero,hidalgo,gimenez,ibanez,ferrer,duran,arias,carmona,crespo,roman,velasco,saez,rojas,mendoza,vargas,quispe,mamani,choque,condori,huanca,apaza,ticona,limachi,gutierres,villca,copa,colque,mercado,salazar,paredes,arce,zambrana,peralta,soria,camacho,miranda,espinoza,cardenas,aguirre,figueroa,rios,sandoval,chavez,contreras,silva,guzman,salinas,valdez,estrada,maldonado,trujillo,cervantes,orozco,velazquez,cuevas,ponce,ochoa,avila,ibarra,rosales,acosta,zamora,sahonero,ampuero,smith,johnson,williams,jones,davis,wilson,anderson,thompson,harris,robinson,lewis,allen,mitchell,roberts,phillips,campbell,evans,edwards,collins,stewart,morris,rogers,reed,morgan,cooper,richardson,howard,ward,peterson,gray,james,watson,brooks,sanders,price,bennett,barnes,ross,henderson,coleman,jenkins,perry,powell,patterson,hughes,washington,butler,simmons,foster,gonzales,bryant,alexander,russell,griffin,hayes,myers,ford,hamilton,graham,sullivan,wallace,woods,cole,west,jordan,owens,reynolds,fisher,ellis,harrison,gibson,mcdonald,marshall".split(","))
# Real words a rule would otherwise catch (ivan/iban, niger, golfo...).
ALLOW = set("vea,iban,jugo,marsella,xanax,hose,marry,geese,scoot,booby,lorry,ela,ami,dona,mah,zara,abba,niger,mongol,mongols,mongoles,mongolia,bolera,bastaria,retrasando,rewarded,regarded,travels,travel,puts,putz,sora,zora".split(","))

NAMES = set(NAMES_ES) | (set(NAMES_EN) - EN_AMBIGUOUS)
BAD = set(BAD_ES) | set(BAD_EN)
SUFFIXES = {"s", "as", "os", "es", "ita", "ito", "itas", "itos", "isa", "isas",
            "aso", "asa", "asos", "asas", "ote", "ota", "ona", "ones", "ero",
            "era", "eros", "eras", "ada", "adas", "iyo", "iya"}


def fold(text):
    text = text.lower().replace("ñ", "n")
    return "".join(c for c in unicodedata.normalize("NFD", text)
                   if unicodedata.category(c) != "Mn")


def word_key(w):
    """Python twin of public.word_key()."""
    w = re.sub(r"(.)\1+", r"\1", w)
    w = w.replace("ph", "f")
    w = re.sub(r"g([ei])", r"h\1", w)
    w = re.sub(r"c([ei])", r"s\1", w)
    w = re.sub(r"qu([ei])", r"k\1", w)
    w = re.sub(r"gu([ei])", r"g\1", w)
    w = w.replace("ch", "9").replace("c", "k").replace("q", "k").replace("9", "ch")
    w = w.replace("ll", "y")
    w = w.translate(str.maketrans("jxzv", "hhsb"))
    w = re.sub(r"y(?![aeiou])", "i", w)
    return re.sub(r"(.)\1+", r"\1", w)


NAME_KEYS = {word_key(n) for n in NAMES}
BAD_KEYS = {word_key(b) for b in BAD}
STEMS = {k[:-1] if k[-1] in "aeo" else k for k in BAD_KEYS if len(k) >= 5} | {"put"}


def lev(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def is_insult(w):
    k = word_key(w)
    if any(k in (b, b + "s", b + "es") for b in BAD_KEYS):
        return True
    if any(k.startswith(s) and k[len(s):] in SUFFIXES for s in STEMS):
        return True
    return len(k) >= 8 and any(
        len(b) >= 8 and abs(len(b) - len(k)) <= 1 and lev(b, k) <= 1 for b in BAD_KEYS)


def main():
    words = set(ALLOW)
    for lang in ("es", "en"):
        with urllib.request.urlopen(SOURCE.format(lang=lang)) as response:
            for line in response.read().decode("utf-8").splitlines():
                w = fold(line.split(" ")[0])
                if not re.fullmatch(r"[a-z]+", w) or w in ALLOW:
                    continue
                if w in NAMES or w in SURNAMES or word_key(w) in NAME_KEYS:
                    continue
                if is_insult(w):
                    continue
                words.add(w)
    rows = sorted(words)
    # One word per line. supabase/seed/load_common_words.sql makes the
    # database download this file from GitHub (pg_net) and load it.
    with open("supabase/seed/common_words.txt", "w", encoding="utf-8") as out:
        out.write("\n".join(rows) + "\n")
    print(len(rows), "words")


if __name__ == "__main__":
    main()
