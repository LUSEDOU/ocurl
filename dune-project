(lang dune 3.15)

(name ocurl)

(generate_opam_files true)

(source
 (github LUSEDOU/ocurl))

(authors "LUSEDOU")

(maintainers "LUSEDOU < lusedou@gmail.com")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name ocurl)
 (synopsis "curl pipeline for OCaml")
 (description "OCurl is a curl pipeline that allows you to make HTTP requests with in OCaml. It is a wrapper around the libcurl library.")
 (depends ocaml dune)
 (tags
   (topics "http" "curl" "ocaml" "web")))
  ; (topics "" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
