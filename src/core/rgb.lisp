(in-package :dufy-core)

;;;
;;; RGB Color Space
;;;
(define-colorspace rgb ((r double-float)
                        (g double-float)
                        (b double-float))
  :illuminant :rgbspace)
(define-colorspace lrgb ((lr double-float)
                         (lg double-float)
                         (lb double-float))
  :illuminant :rgbspace)
(define-colorspace qrgb ((qr integer)
                         (qg integer)
                         (qb integer))
  :illuminant :rgbspace
  :clamp :clampable)
(define-colorspace int ((int integer))
  :illuminant :rgbspace
  :clamp :always-clamped)

(defun gen-linearizer (gamma)
  "Returns a linearization function for a given gamma value."
  (let ((gamma (float gamma 1d0)))
    #'(lambda (x)
	(declare (optimize (speed 3) (safety 1))
		 (double-float x))
	(if (plusp x)
	    (expt x gamma)
	    (- (expt (- x) gamma))))))

(defun gen-delinearizer (gamma)
  "Returns a gamma-correction function for a given gamma value."
  (let ((/gamma (/ (float gamma 1d0))))
    #'(lambda (x)
	(declare (optimize (speed 3) (safety 1))
		 (double-float x))
	(if (plusp x)
	    (expt x /gamma)
	    (- (expt (- x) /gamma))))))

(defstruct (rgbspace (:constructor %make-rgbspace)
		     (:copier nil))
  "Structure of RGB space, including encoding characteristics"
  ;; primary coordinates in xyY space.
  (xr 0d0 :type double-float) (yr 0d0 :type double-float)
  (xg 0d0 :type double-float) (yg 0d0 :type double-float)
  (xb 0d0 :type double-float) (yb 0d0 :type double-float)
  
  (illuminant +illum-d65+ :type illuminant)
  (to-xyz-matrix +identity-matrix+ :type (simple-array double-float (3 3)))
  (from-xyz-matrix +identity-matrix+ :type (simple-array double-float (3 3)))

  ;; nominal range of linear values
  (lmin 0d0 :type double-float)
  (lmax 1d0 :type double-float)
  
  (linearizer (rcurry #'float 1d0) :type (function * double-float))
  (delinearizer (rcurry #'float 1d0) :type (function * double-float))

  ;; nominal range of gamma-corrected values
  (min 0d0 :type double-float)
  (max 1d0 :type double-float)
  (length 1d0 :type double-float) ; length of the interval [min, max]
  (/length 1d0 :type double-float)
  (normal t :type boolean) ; t, if min = 0d0 and max = 1d0

  ;; quantization
  (bit-per-channel 8 :type (integer 1 #.(floor (log most-positive-fixnum 2))))
  (qmax 255 :type (integer 1 #.most-positive-fixnum) :read-only t) ; max. of quantized values
  (qmax-float 255d0 :type double-float)
  (length/qmax-float (float 1/255 1d0) :type double-float)
  (qmax-float/length 255d0 :type double-float))


(defun make-rgbspace (xr yr xg yg xb yb &key (illuminant +illum-d65+) (lmin 0d0) (lmax 1d0) (linearizer (rcurry #'float 1d0)) (delinearizer (rcurry #'float 1d0)) (bit-per-channel 8) (force-normal nil))
  "LINEARIZER and DELINEARIZER must be (FUNCTION * DOUBLE-FLOAT).
If FORCE-NORMAL is T, the nominal range of gamma-corrected value is
forcibly set to [0, 1]."
  (declare (optimize (speed 3) (safety 1))
	   ((function * double-float) linearizer delinearizer))
  (with-double-float (xr yr xg yg xb yb)
    (let ((coordinates
	   (make-array '(3 3)
		       :element-type 'double-float
		       :initial-contents
		       (list (list xr xg xb)
			     (list yr yg yb)
			     (list (- 1d0 xr yr) (- 1d0 xg yg) (- 1d0 xb yb))))))
      (multiple-value-bind (sr sg sb)
	  (multiply-mat-vec (invert-matrix33 coordinates)
			    (illuminant-x illuminant)
			    1d0
			    (illuminant-z illuminant))
	(let* ((mat
		(make-array '(3 3)
			    :element-type 'double-float
			    :initial-contents
			    (list (list (* sr (aref coordinates 0 0))
					(* sg (aref coordinates 0 1))
					(* sb (aref coordinates 0 2)))
				  (list (* sr (aref coordinates 1 0))
					(* sg (aref coordinates 1 1))
					(* sb (aref coordinates 1 2)))
				  (list (* sr (aref coordinates 2 0))
					(* sg (aref coordinates 2 1))
					(* sb (aref coordinates 2 2))))))
	       (min (if force-normal 0d0 (funcall delinearizer lmin)))
	       (max (if force-normal 1d0 (funcall delinearizer lmax)))
	       (normal (if (and (= min 0d0) (= max 1d0))
			   t nil))
	       (qmax (- (expt 2 bit-per-channel) 1))
	       (qmax-float (float qmax 1d0))
	       (len (- max min)))
	  (%make-rgbspace :xr xr :yr yr :xg xg :yg yg :xb xb :yb yb
			  :illuminant illuminant
			  :linearizer linearizer
			  :delinearizer delinearizer
			  :to-xyz-matrix mat
			  :from-xyz-matrix (invert-matrix33 mat)
			  :lmin lmin
			  :lmax lmax
			  :min min
			  :max max
			  :length len
                          :/length (/ len)
			  :normal normal
			  :bit-per-channel bit-per-channel
			  :qmax qmax
			  :qmax-float qmax-float
			  :qmax-float/length (/ qmax-float len)
			  :length/qmax-float (/ len qmax-float)))))))

(defvar +srgb+) ; later defined

(define-primary-converter xyz lrgb (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (multiply-mat-vec (rgbspace-from-xyz-matrix rgbspace)
		    (float x 1d0)
		    (float y 1d0)
		    (float z 1d0)))

(define-primary-converter lrgb xyz (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (multiply-mat-vec (rgbspace-to-xyz-matrix rgbspace)
		    (float lr 1d0)
		    (float lg 1d0)
		    (float lb 1d0)))



;;;
;;; Linear RGB, gamma-corrected RGB and quantized RGB
;;;


(defun lrgb-out-of-gamut-p (lr lg lb &key (rgbspace +srgb+) (threshold 1d-4))
  "Returns true, if at least one of LR, LG and LB is outside the
interval [RGBSPACE-LMIN - THRESHOLD, RGBSPACE-LMAX + THRESHOLD]"
  (let ((inf (- (rgbspace-lmin rgbspace) threshold))
	(sup (+ (rgbspace-lmax rgbspace) threshold)))
    (not (and  (<= inf lr sup)
	       (<= inf lg sup)
	       (<= inf lb sup)))))

(defun linearize (x &optional (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (funcall (rgbspace-linearizer rgbspace) (float x 1d0)))

(defun delinearize (x &optional (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (funcall (rgbspace-delinearizer rgbspace) (float x 1d0)))

(define-primary-converter lrgb rgb (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (let ((delin (rgbspace-delinearizer rgbspace)))
    (values (funcall delin (float lr 1d0))
	    (funcall delin (float lg 1d0))
	    (funcall delin (float lb 1d0)))))

(define-primary-converter rgb lrgb (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (let ((lin (rgbspace-linearizer rgbspace)))
    (values (funcall lin (float r 1d0))
	    (funcall lin (float g 1d0))
	    (funcall lin (float b 1d0)))))

(defun rgb-out-of-gamut-p (r g b &key (rgbspace +srgb+) (threshold 1d-4))
  "Returns true, if at least one of R, G and B is outside the interval
[RGBSPACE-MIN - THRESHOLD, RGBSPACE-MAX + THRESHOLD]"
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (threshold)
    (let ((inf (- (rgbspace-min rgbspace) threshold))
	  (sup (+ (rgbspace-max rgbspace) threshold)))
      (not (and (<= inf r sup)
		(<= inf g sup)
		(<= inf b sup))))))

(defconverter xyz rgb)
;; (declaim (inline xyz-to-rgb))
;; (defun xyz-to-rgb (x y z &key (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'lrgb-to-rgb
;;     (xyz-to-lrgb (float x 1d0) (float y 1d0) (float z 1d0)
;;                  :rgbspace rgbspace)
;;     :rgbspace rgbspace))


(defun bench-xyz-to-rgb (&optional (num 5000000))
  (time-median 10
    (dotimes (i num)
      (xyz-to-rgb 0.1 0.2 0.3))))

(defconverter rgb xyz)
;; (declaim (inline rgb-to-xyz))
;; (defun rgb-to-xyz (r g b &key (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'lrgb-to-xyz
;;     (rgb-to-lrgb (float r 1d0) (float g 1d0) (float b 1d0)
;;                  :rgbspace rgbspace)
;;     :rgbspace rgbspace))



(declaim (inline qrgb-out-of-gamut-p))
(defun qrgb-out-of-gamut-p (qr qg qb &key (rgbspace +srgb+) (threshold 0))
  (declare (optimize (speed 3) (safety 1))
	   (integer qr qg qb threshold))
  (let ((inf (- threshold))
	(sup (+ (rgbspace-qmax rgbspace) threshold)))
    (not (and (<= inf qr sup)
	      (<= inf qg sup)
	      (<= inf qb sup)))))

(define-primary-converter rgb qrgb (&key (rgbspace +srgb+) (clamp t))
  "Quantizes RGB values from [RGBSPACE-MIN, RGBSPACE-MAX] ([0, 1], typically) to {0, 1,
..., RGBSPACE-QMAX} ({0, 1, ..., 255}, typically), though it accepts
all the real values."
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (r g b)
    (let ((min (rgbspace-min rgbspace))
	  (qmax-float/length (rgbspace-qmax-float/length rgbspace))
	  (qmax (rgbspace-qmax rgbspace)))
      (if clamp
          (values (clamp (round (* (- r min) qmax-float/length)) 0 qmax)
                  (clamp (round (* (- g min) qmax-float/length)) 0 qmax)
                  (clamp (round (* (- b min) qmax-float/length)) 0 qmax))
          (values (round (* (- r min) qmax-float/length))
                  (round (* (- g min) qmax-float/length))
                  (round (* (- b min) qmax-float/length)))))))


(define-primary-converter qrgb rgb (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1))
	   (integer qr qg qb))
  (let ((min (rgbspace-min rgbspace))
	(length/qmax-float (rgbspace-length/qmax-float rgbspace)))
    (values (+ min (* qr length/qmax-float))
	    (+ min (* qg length/qmax-float))
	    (+ min (* qb length/qmax-float)))))

(defconverter lrgb qrgb)
;; (declaim (inline lrgb-to-qrgb))
;; (defun lrgb-to-qrgb (lr lg lb &key (rgbspace +srgb+) (clamp t))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-qrgb
;;     (lrgb-to-rgb (float lr 1d0) (float lg 1d0) (float lb 1d0)
;;                  :rgbspace rgbspace)
;;     :rgbspace rgbspace
;;     :clamp clamp))


(defconverter qrgb lrgb)
;; (declaim (inline qrgb-to-lrgb))
;; (defun qrgb-to-lrgb (qr qg qb &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1))
;;            (integer qr qg qb))
;;   (multiple-value-call #'rgb-to-lrgb
;;     (qrgb-to-rgb qr qg qb :rgbspace rgbspace)
;;     :rgbspace rgbspace))


(defun bench-qrgb-to-lrgb (&optional (num 8000000))
  (time-median 10
    (dotimes (i num)
      (qrgb-to-lrgb 100 200 50))))


(defconverter xyz qrgb)
;; (declaim (inline xyz-to-qrgb))
;; (defun xyz-to-qrgb (x y z &key (rgbspace +srgb+) (clamp t))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-qrgb
;;     (xyz-to-rgb (float x 1d0) (float y 1d0) (float z 1d0) rgbspace)
;;     :rgbspace rgbspace
;;     :clamp clamp))


(defconverter qrgb xyz)
;; (declaim (inline qrgb-to-xyz))
;; (defun qrgb-to-xyz (qr qg qb &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1))
;; 	   (integer qr qg qb))
;;   (multiple-value-call #'rgb-to-xyz
;;     (qrgb-to-rgb qr qg qb rgbspace)
;;     rgbspace))


(define-primary-converter qrgb int (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1))
	   (integer qr qg qb))
  (let ((bpc (rgbspace-bit-per-channel rgbspace))
	(qmax (rgbspace-qmax rgbspace)))
    (+ (ash (clamp qr 0 qmax) (+ bpc bpc))
       (ash (clamp qg 0 qmax) bpc)
       (clamp qb 0 qmax))))

(define-primary-converter int qrgb (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1))
	   (integer int))
  (let ((minus-bpc (- (rgbspace-bit-per-channel rgbspace)))
	(qmax (rgbspace-qmax rgbspace)))
    (values (logand (ash int (+ minus-bpc minus-bpc)) qmax)
	    (logand (ash int minus-bpc) qmax)
	    (logand int qmax))))


;; For handling alpha channel.
;; These are improvised and not exported.
(defun qrgba-to-int (qr qg qb qalpha &optional (rgbspace +srgb+) (order :argb))
  "The order can be :ARGB or :RGBA. Note that it is different from the
  'physical' byte order in a machine, which depends on the endianess."
  (declare (optimize (speed 3) (safety 1))
	   (integer qr qg qb qalpha))
  (let* ((bpc (rgbspace-bit-per-channel rgbspace))
	 (2bpc (+ bpc bpc))
	 (qmax (rgbspace-qmax rgbspace)))
    (ecase order
      (:argb (+ (clamp qb 0 qmax)
		(ash (clamp qg 0 qmax) bpc)
		(ash (clamp qr 0 qmax) 2bpc)
		(ash (clamp qalpha 0 qmax) (+ 2bpc bpc))))
      (:rgba (+ (clamp qalpha 0 qmax)
		(ash (clamp qb 0 qmax) bpc)
		(ash (clamp qg 0 qmax) 2bpc)
		(ash (clamp qr 0 qmax) (+ 2bpc bpc)))))))

(defun int-to-qrgba (int &optional (rgbspace +srgb+) (order :argb))
  "The order can be :ARGB or :RGBA. Note that it is different from the
  'physical' byte order in a machine, which depends on the endianess."
  (declare (optimize (speed 3) (safety 1))
	   (integer int))
  (let* ((-bpc (- (rgbspace-bit-per-channel rgbspace)))
	 (-2bpc (+ -bpc -bpc))
	 (qmax (rgbspace-qmax rgbspace)))
    (ecase order
      (:argb (values (logand (ash int -2bpc) qmax)
		     (logand (ash int -bpc) qmax)
		     (logand int qmax)
		     (logand (ash int (+ -2bpc -bpc)) qmax)))
      (:rgba (values (logand (ash int (+ -2bpc -bpc)) qmax)
		     (logand (ash int -2bpc) qmax)
		     (logand (ash int -bpc) qmax)
		     (logand int qmax))))))

;; (defun bench-qrgb (&optional (num 10000000))
;;   (time-median 10 (dotimes (i num)
;;                     (multiple-value-call #'qrgb-to-int
;;                       (int-to-qrgb (random #.(expt 2 64))
;;                                    :rgbspace +bg-srgb-16+)
;;                       :rgbspace +bg-srgb-16+))))



(defconverter int rgb)
;; (declaim (inline int-to-rgb))
;; (defun int-to-rgb (int &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'qrgb-to-rgb
;;     (int-to-qrgb int rgbspace)
;;     rgbspace))



(defconverter rgb int)
;; (declaim (inline rgb-to-int))
;; (defun rgb-to-int (r g b &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (with-double-float (r g b)
;;     (multiple-value-call #'qrgb-to-int
;;       (rgb-to-qrgb r g b :rgbspace rgbspace)
;;       rgbspace)))


(defconverter int lrgb)
;; (declaim (inline int-to-lrgb))
;; (defun int-to-lrgb (int &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'qrgb-to-lrgb
;;     (int-to-qrgb int rgbspace)
;;     rgbspace))

(defconverter lrgb int)
;; (declaim (inline lrgb-to-int))
;; (defun lrgb-to-int (lr lg lb &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-int
;;     (lrgb-to-rgb (float lr 1d0) (float lg 1d0) (float lb 1d0) rgbspace)
;;     rgbspace))


(defconverter int xyz)
;; (declaim (inline int-to-xyz))
;; (defun int-to-xyz (int &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1))
;; 	   (integer int))
;;   (multiple-value-call #'qrgb-to-xyz
;;     (int-to-qrgb int rgbspace)
;;     rgbspace))

(defconverter xyz int)
;; (declaim (inline xyz-to-int))
;; (defun xyz-to-int (x y z &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'qrgb-to-int
;;     (xyz-to-qrgb (float x 1d0) (float y 1d0) (float z 1d0) :rgbspace rgbspace)
;;     rgbspace))




;;;
;;; HSV/HSL
;;;

(define-colorspace hsv ((hue double-float)
                        (sat double-float)
                        (val double-float))
  :illuminant :rgbspace)
(define-colorspace hsl ((hue double-float)
                        (sat double-float)
                        (lum double-float))
  :illuminant :rgbspace)

(defmacro macrolet-applied-only-when (test definitions &body body)
  `(if ,test
       (macrolet ,definitions
         ,@body)
       (macrolet ,(loop for def in definitions
                        collect `(,(car def) (arg) arg))
         ,@body)))

(define-primary-converter hsv rgb (&key (rgbspace +srgb+))
  "HUE is in the circle group R/360. The nominal range of SAT and VAL is [0,
1]; all the real values outside the interval are also acceptable."
  (declare (optimize (speed 3) (safety 1)))
  (let ((hue (the (double-float 0d0 360d0) (mod (float hue 1d0) 360d0)))
        (sat (float sat 1d0))
        (val (float val 1d0)))
    (let* ((c (* val sat))
           (h-prime (* hue 1/60))
           (h-prime-int (floor h-prime))
           (x (* c (- 1d0 (abs (- (mod h-prime 2d0) 1d0)))))
           (base (- val c)))
      (macrolet-applied-only-when (not (rgbspace-normal rgbspace))
          ((local-lerp (x)
                       `(+ (rgbspace-min rgbspace)
                           (* ,x (rgbspace-length rgbspace)))))
        (cond ((= sat 0d0) (values base base base))
              ((= 0 h-prime-int) (values (local-lerp (+ base c))
                                         (local-lerp (+ base x))
                                         (local-lerp base)))
              ((= 1 h-prime-int) (values (local-lerp (+ base x))
                                         (local-lerp (+ base c))
                                         (local-lerp base)))
              ((= 2 h-prime-int) (values (local-lerp base)
                                         (local-lerp (+ base c))
                                         (local-lerp (+ base x))))
              ((= 3 h-prime-int) (values (local-lerp base)
                                         (local-lerp (+ base x))
                                         (local-lerp (+ base c))))
              ((= 4 h-prime-int) (values (local-lerp (+ base x))
                                         (local-lerp base)
                                         (local-lerp (+ base c))))
              ((= 5 h-prime-int) (values (local-lerp (+ base c))
                                         (local-lerp base)
                                         (local-lerp (+ base x))))
              (t (values 0d0 0d0 0d0))) ; for avoiding warnings
        ))))

(defconverter hsv qrgb)
;; (declaim (inline hsv-to-qrgb))
;; (defun hsv-to-qrgb (hue sat val &key (rgbspace +srgb+) (clamp t))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-qrgb
;;     (hsv-to-rgb hue sat val)
;;     :rgbspace rgbspace
;;     :clamp clamp))

(defconverter hsv xyz)
;; (declaim (inline hsv-to-xyz))
;; (defun hsv-to-xyz (hue sat val &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-xyz
;;     (hsv-to-rgb hue sat val)
;;     rgbspace))

(defmacro let-if (test bindings &body body)
  `(if ,test
       (let ,(loop for x in bindings
                   collect (list (first x) (second x)))
         ,@body)
       (let ,(loop for x in bindings
                   collect (list (first x) (third x)))
         ,@body)))

(define-primary-converter rgb hsv (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (macrolet ((local-lerp (x) ; scale to the range [0, 1]
               `(* (- (float ,x 1d0) (rgbspace-min rgbspace))
                   (rgbspace-/length rgbspace))))
    (let-if (rgbspace-normal rgbspace)
        ((r (float r 1d0) (local-lerp r))
         (g (float g 1d0) (local-lerp g))
         (b (float b 1d0) (local-lerp b)))
      (let* ((maxrgb (max r g b))
             (minrgb (min r g b))
             (s (if (= maxrgb 0d0)
                    0d0
                    (/ (- maxrgb minrgb) maxrgb)))
             (h (cond ((= minrgb maxrgb) 0d0)
                      ((= minrgb b) (+ (* 60d0 (/ (- g r) (- maxrgb minrgb))) 60d0))
                      ((= minrgb r) (+ (* 60d0 (/ (- b g) (- maxrgb minrgb))) 180d0))
                      ((= minrgb g) (+ (* 60d0 (/ (- r b) (- maxrgb minrgb))) 300d0)))))
        (values h s maxrgb)))))

(defconverter qrgb hsv)
;; (declaim (inline qrgb-to-hsv))
;; (defun qrgb-to-hsv (qr qg qb &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1))
;; 	   (integer qr qg qb))
;;   (multiple-value-call #'rgb-to-hsv
;;     (qrgb-to-rgb qr qg qb rgbspace)))

(defconverter xyz hsv)
;; (declaim (inline xyz-to-hsv))
;; (defun xyz-to-hsv (x y z &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-hsv
;;     (xyz-to-rgb x y z rgbspace)))


(define-primary-converter hsl rgb (&key (rgbspace +srgb+))
  "HUE is in the circle group R/360. The nominal range of SAT and LUM is [0,
1]; all the real values outside the interval are also acceptable."
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (hue sat lum)
    (let* ((tmp (* 0.5d0 sat (- 1d0 (abs (- (* lum 2d0) 1d0)))))
	   (max (+ lum tmp))
	   (min (- lum tmp))
	   (delta (- max min))
	   (h-prime (floor (the (double-float 0d0 6d0)
				(* (mod hue 360d0) 1/60)))))
      (macrolet-applied-only-when (not (rgbspace-normal rgbspace))
          ((local-lerp (x)
                       `(+ (rgbspace-min rgbspace)
                           (* ,x (rgbspace-length rgbspace)))))
        (cond ((= sat 0d0) (values max max max))
              ((= 0 h-prime) (values (local-lerp max)
                                     (local-lerp (+ min (* delta hue 1/60)))
                                     (local-lerp min)))
              ((= 1 h-prime) (values (local-lerp (+ min (* delta (- 120d0 hue) 1/60)))
                                     (local-lerp max)
                                     (local-lerp min)))
              ((= 2 h-prime) (values (local-lerp min)
                                     (local-lerp max)
                                     (local-lerp (+ min (* delta (- hue 120d0) 1/60)))))
              ((= 3 h-prime) (values (local-lerp min)
                                     (local-lerp (+ min (* delta (- 240d0 hue) 1/60)))
                                     (local-lerp max)))
              ((= 4 h-prime) (values (local-lerp (+ min (* delta (- hue 240d0) 1/60)))
                                     (local-lerp min)
                                     (local-lerp max)))
              ((= 5 h-prime) (values (local-lerp max)
                                     (local-lerp min)
                                     (local-lerp (+ min (* delta (- 360d0 hue) 1/60)))))
              (t (values 0d0 0d0 0d0) ; for avoiding warnings
                 ))))))
 

(defconverter hsl qrgb)
;; (declaim (inline hsl-to-qrgb))
;; (defun hsl-to-qrgb (hue sat lum &key (rgbspace +srgb+) (clamp t))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-qrgb
;;     (hsl-to-rgb hue sat lum)
;;     :rgbspace rgbspace
;;     :clamp clamp))

(defconverter hsl xyz)
;; (declaim (inline hsl-to-xyz))
;; (defun hsl-to-xyz (hue sat lum &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-xyz
;;     (hsl-to-rgb hue sat lum)
;;     rgbspace))

(define-primary-converter rgb hsl (&key (rgbspace +srgb+))
  (declare (optimize (speed 3) (safety 1)))
  (macrolet ((local-lerp (x) ; scale to the range [0, 1]
               `(* (- (float ,x 1d0) (rgbspace-min rgbspace))
                   (rgbspace-/length rgbspace))))
    (let-if (rgbspace-normal rgbspace)
        ((r (float r 1d0) (local-lerp r))
         (g (float g 1d0) (local-lerp g))
         (b (float b 1d0) (local-lerp b)))
      (let ((min (min r g b))
            (max (max r g b)))
        (let ((hue (cond ((= min max) 0d0)
                         ((= min b) (+ 60d0 (* 60d0 (/ (- g r) (- max min)))))
                         ((= min r) (+ 180d0 (* 60d0 (/ (- b g) (- max min)))))
                         ((= min g) (+ 300d0 (* 60d0 (/ (- r b) (- max min))))))))
          (values hue
                  (let ((denom (- 1d0 (abs (+ max min -1d0)))))
                    (if (zerop denom)
                        0d0
                        (/ (- max min) denom)))
                  (* 0.5d0 (+ max min))))))))

(defconverter qrgb hsl)
;; (declaim (inline qrgb-to-hsl))
;; (defun qrgb-to-hsl (qr qg qb &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-hsl
;;     (qrgb-to-rgb qr qg qb rgbspace)))


(defconverter xyz hsl)
;; (declaim (inline xyz-to-hsl))
;; (defun xyz-to-hsl (x y z &optional (rgbspace +srgb+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'rgb-to-hsl
;;     (xyz-to-rgb x y z rgbspace)))

