# Bundled reference paintings

These four images are bundled as offline reference anchors for Evolving
Impressionist. Each is a faithful reproduction of a Claude Monet painting and
is stored as a 1280-pixel-wide PNG so the complete catalog remains a reasonable
size for the repository.

The Art Institute of Chicago marks every museum record below as **CC0 Public
Domain Designation**. Its [Open Access Images policy][aic-open-access] permits
free, unrestricted commercial and noncommercial reuse of images bearing that
designation. The Wikimedia Commons file records used for the actual downloads
also mark each reproduction as public domain.

| Runtime file | Artwork | Artist | Date | Institution | Museum record | Download record | Rights status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `monet-water-lilies.png` | *Water Lilies* | Claude Monet | 1906 | Art Institute of Chicago | [AIC 1933.1157][aic-water-lilies] | [Wikimedia Commons][commons-water-lilies] | AIC CC0 Public Domain Designation; Commons Public Domain Mark / PD-Art |
| `monet-water-lily-pond.png` | *Water Lily Pond* (Japanese footbridge) | Claude Monet | 1900 | Art Institute of Chicago | [AIC 1933.441][aic-water-lily-pond] | [Wikimedia Commons][commons-water-lily-pond] | AIC CC0 Public Domain Designation; Commons public-domain/CC0 record |
| `monet-stacks-of-wheat.png` | *Stacks of Wheat (End of Summer)* | Claude Monet | 1890–91 | Art Institute of Chicago | [AIC 1985.1103][aic-stacks] | [Wikimedia Commons][commons-stacks] | AIC CC0 Public Domain Designation; Commons public-domain/PD-Art record |
| `monet-beach-at-sainte-adresse.png` | *The Beach at Sainte-Adresse* | Claude Monet | 1867 | Art Institute of Chicago | [AIC 1933.439][aic-beach] | [Wikimedia Commons][commons-beach] | AIC CC0 Public Domain Designation; Commons public-domain/PD-Art record |

The default runtime reference is `monet-water-lilies.png`.

## Reproducing the assets

The following commands download the exact Commons originals and convert them
to the repository PNG dimensions with macOS `sips`:

```sh
mkdir -p /tmp/evolving-paintings

curl -fL 'https://upload.wikimedia.org/wikipedia/commons/a/aa/Claude_Monet_-_Water_Lilies_-_1906%2C_Ryerson.jpg' \
  -o /tmp/evolving-paintings/monet-water-lilies.jpg
curl -fL 'https://upload.wikimedia.org/wikipedia/commons/0/03/Claude_Monet_-_Water_Lily_Pond_-_1933.441_-_Art_Institute_of_Chicago.jpg' \
  -o /tmp/evolving-paintings/monet-water-lily-pond.jpg
curl -fL 'https://upload.wikimedia.org/wikipedia/commons/6/68/Claude_Monet_-_Stacks_of_Wheat_%28End_of_Summer%29_-_1985.1103_-_Art_Institute_of_Chicago.jpg' \
  -o /tmp/evolving-paintings/monet-stacks-of-wheat.jpg
curl -fL 'https://upload.wikimedia.org/wikipedia/commons/0/01/Claude_Monet_-_The_Beach_at_Sainte-Adresse_-_Google_Art_Project.jpg' \
  -o /tmp/evolving-paintings/monet-beach-at-sainte-adresse.jpg

for source in /tmp/evolving-paintings/*.jpg; do
  name=$(basename "$source" .jpg)
  sips --resampleWidth 1280 -s format png "$source" \
    --out "Sources/EvolvingImpressionistCore/Resources/Paintings/$name.png"
done
```

[aic-open-access]: https://www.artic.edu/open-access/open-access-images
[aic-water-lilies]: https://www.artic.edu/artworks/16568/water-lilies
[aic-water-lily-pond]: https://www.artic.edu/artworks/87088/water-lily-pond
[aic-stacks]: https://www.artic.edu/artworks/64818/stacks-of-wheat-end-of-summer
[aic-beach]: https://www.artic.edu/artworks/14598/the-beach-at-sainte-adresse
[commons-water-lilies]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_1906%2C_Ryerson.jpg
[commons-water-lily-pond]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lily_Pond_-_1933.441_-_Art_Institute_of_Chicago.jpg
[commons-stacks]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Stacks_of_Wheat_%28End_of_Summer%29_-_1985.1103_-_Art_Institute_of_Chicago.jpg
[commons-beach]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_The_Beach_at_Sainte-Adresse_-_Google_Art_Project.jpg
