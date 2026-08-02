# MangaReader Glossary

- Book: a leaf item that directly or transitively contains page images. A
  folder with images or an archive is a Book.
- Collection: a container that organizes Books. A folder whose children are
  containers, or a resolved mixed container, is a Collection.
- Mixed Container: a folder or archive that contains both direct page images
  and child containers, and therefore needs a user decision before it can be
  classified.
- Page: an image inside a Book, ordered naturally and identified by its
  archive or relative path.
- Derived Cache: rebuildable output such as thumbnails, extracted pages, and
  enhanced pages. It never contains source-of-truth user data.
- Profile: the runtime contract for running an ONNX model, including tensor
  names, scale, tiling, colorspace, normalization, alpha handling, and
  execution provider.
- Source Identity: the stable fingerprint that lets metadata survive a move or
  rename performed outside the app.
