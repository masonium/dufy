(cl:in-package :cl-user)

(defpackage dufy.package.def.munsell
  (:use :cl))
(in-package :dufy.package.def.munsell)


(defpackage dufy.munsell
  (:use :cl :dufy.core :alexandria)
  (:import-from :dufy.core
                :with-double-float
                :subtract-with-mod
                :time-after-gc)
  (:export :invalid-mhvc-error
           :munsellspec-parse-error
           :large-approximation-error
           
           :munsell-value-to-y
           :y-to-munsell-value
           :mhvc-out-of-mrd-p
           :mhvc-to-xyy
           :mhvc-to-xyz
           :mhvc-to-xyz-illum-c
           :mhvc-to-lrgb
           :mhvc-to-qrgb
           :mhvc-to-lchab-illum-c
           :mhvc-to-munsell
           :munsell-to-mhvc
           :munsell-out-of-mrd-p
           :munsell-to-lchab-illum-c
           :munsell-to-xyz
           :munsell-to-xyz-illum-c
           :munsell-to-xyy
           :munsell-to-qrgb
           :max-chroma-in-mrd
           :lchab-to-mhvc-illum-c
           :lchab-to-munsell-illum-c
           :xyz-to-mhvc
           :xyz-to-munsell
           :*maximum-chroma*))