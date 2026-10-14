# Training data and licences (money model v2)

NoteLens is meant to be sold, so every image source used for the money model
is listed here with its licence. `training/prepare_dataset.py` writes the same
table for each build to `training/data/<run>/licenses.csv`.

| Source | What | Licence | OK to sell? |
|---|---|---|---|
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Banknotes_of_Kenya), Kenyan notes and coins | 42 scans and photos, 2010 and 2019 series, 1/5/10/20 shilling coins | CC0 or CC BY-SA, per file | Yes. CC BY-SA files need attribution in the About screen |
| [World Paper Money](https://www.kaggle.com/datasets/abhaysharma01702/world-paper-money-banknotes-across-regions) (Kaggle), Kenya and Uganda | 92 KES and 100 UGX catalogue scans, hand-labelled from contact sheets | **CC BY-NC 4.0** | **No** |
| [Egyptian new currency with coins](https://www.kaggle.com/datasets/samuelayman/egyptian-new-currency-with-coins) | EGP 1–200 notes, including the new polymer 10 and 20, plus 50 piastre and 1 pound coins | Apache 2.0 | Yes |
| [Indian currency notes classifier](https://www.kaggle.com/datasets/gauravsahani/indian-currency-notes-classifier) | INR 10–2000 notes, about 150 images | DbCL 1.0 | Yes |
| [Indian coin images](https://www.kaggle.com/datasets/mssomanna/indian-coin-images-dataset-incl-fake-coins) | INR 1, 2 and 5 rupee coins | CC BY 4.0 | Yes, with attribution |
| [USD bill classification](https://www.kaggle.com/datasets/aishwaryatechie/usd-bill-classification-dataset) | USD 1/2/5/10/50/100 notes | MIT | Yes |
| [Roboflow 100 "currency"](https://huggingface.co/datasets/Francesco/currency-v4f8j) | Real table-top photos of USD bills and coins, boxes cropped | CC BY 4.0 | Yes, with attribution |
| [House rooms and streets](https://www.kaggle.com/datasets/mikhailma/house-rooms-streets-image-dataset) | "No money" background, and backdrops for the synthetic composites | CC0 | Yes |

## Before selling

1. **Replace World Paper Money.** It is the only bulk source for UGX and the
   only one for some KES notes, and its licence forbids commercial use. The
   build trained with it is for testing on your own phone. To replace it:
   - Photograph real notes: 30 to 60 photos per note, front and back, in
     hands, on tables, in poor light. Put them in `training/raw/own_photos/<label>/`,
     for example `KES_100/`, `UGX_5000/` or `KES_20_coin/`. This is also the
     single biggest accuracy improvement available.
   - Or buy a commercial licence for the scans.
   - Then remove the `kes_ugx_wpm` source from `training/sources.yaml` and
     retrain.
2. Add the attribution lines for the CC BY and CC BY-SA sources to the About
   screen.
3. The Bank of Uganda ([Mendeley UGX dataset](https://data.mendeley.com/datasets/dz9j2hbd47/1),
   CC BY 4.0) would be a commercially usable UGX source. Its server returned
   errors while this build was made, so try again later.

## Not used, and why

- **banknoteworld.com** product photos: the site blocks automated access
  (Cloudflare bot check), and the photos belong to the shop. To use them, save
  them by hand into `training/raw/own_photos/<label>/` and only if the shop
  agrees.
- The 5 reference repos in `REPO_ANALYSIS.md` section 9 ship no reusable
  training data. jayjmha's code and weights are GPL, with a Korean-only
  dataset. The ideas were re-implemented instead (tracking, approach speed,
  walking corridor).
- The odhiamboatieno Kenyan-Currency-Detector repo ships a trained model but no
  training images, so there is nothing to retrain from.
