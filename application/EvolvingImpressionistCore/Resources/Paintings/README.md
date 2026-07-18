# Bundled reference paintings

These eight images are bundled as offline reference anchors for Evolving
Impressionist. They span five Impressionist artists and are stored as
1280-pixel-wide PNGs. `catalog.json` is the shared Swift/Python source for
profiles, prompt bias, state bias, and long-period rotation.

The Art Institute of Chicago marks every museum record below as **CC0 Public
Domain Designation**. Its [Open Access Images policy][aic-open-access] permits
free, unrestricted commercial and noncommercial reuse of images bearing that
designation. Existing Monet downloads use public-domain Wikimedia Commons
records; the four additional works use the museum's documented IIIF service.

| Runtime file                        | Artwork                                 | Artist       | Date    | Institution              | Museum record                       | Download record                              | Rights status                                                          |
| ----------------------------------- | --------------------------------------- | ------------ | ------- | ------------------------ | ----------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------- |
| `monet-water-lilies.png`            | *Water Lilies*                          | Claude Monet | 1906    | Art Institute of Chicago | [AIC 1933.1157][aic-water-lilies]   | [Wikimedia Commons][commons-water-lilies]    | AIC CC0 Public Domain Designation; Commons Public Domain Mark / PD-Art |
| `monet-water-lily-pond.png`         | *Water Lily Pond* (Japanese footbridge) | Claude Monet | 1900    | Art Institute of Chicago | [AIC 1933.441][aic-water-lily-pond] | [Wikimedia Commons][commons-water-lily-pond] | AIC CC0 Public Domain Designation; Commons public-domain/CC0 record    |
| `monet-stacks-of-wheat.png`         | *Stacks of Wheat (End of Summer)*       | Claude Monet | 1890–91 | Art Institute of Chicago | [AIC 1985.1103][aic-stacks]         | [Wikimedia Commons][commons-stacks]          | AIC CC0 Public Domain Designation; Commons public-domain/PD-Art record |
| `monet-beach-at-sainte-adresse.png` | *The Beach at Sainte-Adresse*           | Claude Monet | 1867    | Art Institute of Chicago | [AIC 1933.439][aic-beach]           | [Wikimedia Commons][commons-beach]           | AIC CC0 Public Domain Designation; Commons public-domain/PD-Art record |
| `renoir-two-sisters.png`            | *Two Sisters (On the Terrace)*           | Pierre-Auguste Renoir | 1881 | Art Institute of Chicago | [AIC 1933.455][aic-renoir] | [AIC IIIF][iiif-renoir] | AIC CC0 Public Domain Designation |
| `pissarro-place-du-havre.png`       | *The Place du Havre, Paris*              | Camille Pissarro | 1893 | Art Institute of Chicago | [AIC 1922.434][aic-pissarro] | [AIC IIIF][iiif-pissarro] | AIC CC0 Public Domain Designation |
| `sisley-watering-place.png`         | *Watering Place at Marly*                | Alfred Sisley | 1875 | Art Institute of Chicago | [AIC 1971.875][aic-sisley] | [AIC IIIF][iiif-sisley] | AIC CC0 Public Domain Designation |
| `morisot-woman-at-her-toilette.png` | *Woman at Her Toilette*                  | Berthe Morisot | 1875–80 | Art Institute of Chicago | [AIC 1924.127][aic-morisot] | [AIC IIIF][iiif-morisot] | AIC CC0 Public Domain Designation |

The default runtime world is `monet-water-lilies.png`. Rotation remains within
the catalog for 24–96 successful generations and uses six blended anchors
between worlds.

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
curl -A 'Mozilla/5.0' -e 'https://www.artic.edu/' -fL \
  'https://www.artic.edu/iiif/2/3a608f55-d76e-fa96-d0b1-0789fbc48f1e/full/1280,/0/default.jpg' \
  -o /tmp/evolving-paintings/renoir-two-sisters.jpg
curl -A 'Mozilla/5.0' -e 'https://www.artic.edu/' -fL \
  'https://www.artic.edu/iiif/2/0ff20364-c795-c2ca-c1e8-e5a848f09554/full/1280,/0/default.jpg' \
  -o /tmp/evolving-paintings/pissarro-place-du-havre.jpg
curl -A 'Mozilla/5.0' -e 'https://www.artic.edu/' -fL \
  'https://www.artic.edu/iiif/2/ed7aa098-e5c9-04dd-b09c-3416d1c56854/full/1280,/0/default.jpg' \
  -o /tmp/evolving-paintings/sisley-watering-place.jpg
curl -A 'Mozilla/5.0' -e 'https://www.artic.edu/' -fL \
  'https://www.artic.edu/iiif/2/78c80988-6524-cec7-c661-a4c0a706d06f/full/1280,/0/default.jpg' \
  -o /tmp/evolving-paintings/morisot-woman-at-her-toilette.jpg

for source in /tmp/evolving-paintings/*.jpg; do
  name=$(basename "$source" .jpg)
  sips --resampleWidth 1280 -s format png "$source" \
    --out "application/EvolvingImpressionistCore/Resources/Paintings/$name.png"
done
```

[aic-open-access]: https://www.artic.edu/open-access/open-access-images
[aic-water-lilies]: https://www.artic.edu/artworks/16568/water-lilies
[aic-water-lily-pond]: https://www.artic.edu/artworks/87088/water-lily-pond
[aic-stacks]: https://www.artic.edu/artworks/64818/stacks-of-wheat-end-of-summer
[aic-beach]: https://www.artic.edu/artworks/14598/the-beach-at-sainte-adresse
[aic-renoir]: https://www.artic.edu/artworks/14655/two-sisters-on-the-terrace
[aic-pissarro]: https://www.artic.edu/artworks/81551/the-place-du-havre-paris
[aic-sisley]: https://www.artic.edu/artworks/37741/watering-place-at-marly
[aic-morisot]: https://www.artic.edu/artworks/11723/woman-at-her-toilette
[iiif-renoir]: https://www.artic.edu/iiif/2/3a608f55-d76e-fa96-d0b1-0789fbc48f1e/full/1280,/0/default.jpg
[iiif-pissarro]: https://www.artic.edu/iiif/2/0ff20364-c795-c2ca-c1e8-e5a848f09554/full/1280,/0/default.jpg
[iiif-sisley]: https://www.artic.edu/iiif/2/ed7aa098-e5c9-04dd-b09c-3416d1c56854/full/1280,/0/default.jpg
[iiif-morisot]: https://www.artic.edu/iiif/2/78c80988-6524-cec7-c661-a4c0a706d06f/full/1280,/0/default.jpg
[commons-water-lilies]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_1906%2C_Ryerson.jpg
[commons-water-lily-pond]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lily_Pond_-_1933.441_-_Art_Institute_of_Chicago.jpg
[commons-stacks]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Stacks_of_Wheat_%28End_of_Summer%29_-_1985.1103_-_Art_Institute_of_Chicago.jpg
[commons-beach]: https://commons.wikimedia.org/wiki/File:Claude_Monet_-_The_Beach_at_Sainte-Adresse_-_Google_Art_Project.jpg
