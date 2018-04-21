;;;
;;; Munsell Color System
;;;

(in-package :dufy)

;; The bradford transformations between D65 and C are frequently used here.
(declaim (inline c-to-d65))
(def-cat-function c-to-d65 +illum-c+ +illum-d65+ :cat +bradford+)

(declaim (inline d65-to-c))
(def-cat-function d65-to-c +illum-d65+ +illum-c+ :cat +bradford+)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *bit-most-positive-fixnum* #.(floor (log most-positive-fixnum 2))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (declaim (double-float *maximum-chroma*))
  (defparameter *maximum-chroma*
    #+(and sbcl 64-bit) #.(float (expt 2 (- *bit-most-positive-fixnum* 10)) 1d0)
    #-(and sbcl 64-bit)  most-positive-double-float
    "The largest chroma which the Munsell converters accepts. It is in
    some cases less than MOST-POSITIVE-DOUBLE-FLOAT because of
    efficiency: e.g. in SBCL (64-bit) it is desirable that a float F
    fulfills (typep (round F) '(SIGNED-BYTE 64))"))


(declaim (ftype (function * (integer 0 50)) max-chroma-in-mrd))
(defun max-chroma-in-mrd (hue40 value &key (use-dark t))
  "Returns the largest chroma in the Munsell renotation data for a
given hue and value."
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (hue40 value)
    (let* ((hue (mod hue40 40d0))
	   (hue1 (floor hue))
	   (hue2 (mod (ceiling hue) 40)))
      (if (or (>= value 1)
	      (not use-dark))
	  (let ((val1 (floor value))
		(val2 (ceiling value)))
	    (min (aref max-chroma-arr hue1 val1)
		 (aref max-chroma-arr hue1 val2)
		 (aref max-chroma-arr hue2 val1)
		 (aref max-chroma-arr hue2 val2)))
	  (let* ((dark-value (* value 5d0))
		 (dark-val1 (floor dark-value))
		 (dark-val2 (ceiling dark-value)))
	    (min (aref max-chroma-arr-dark hue1 dark-val1)
		 (aref max-chroma-arr-dark hue1 dark-val2)
		 (aref max-chroma-arr-dark hue2 dark-val1)
		 (aref max-chroma-arr-dark hue2 dark-val2)))))))

(declaim (inline munsel-value-to-y
		 munsell-value-to-lstar))
(declaim (ftype (function * double-float) munsell-value-to-y))
(defun munsell-value-to-y (v)
  "Converts Munsell value to Y, whose nominal range is [0, 1]. The
formula is based on ASTM D1535-08e1:"
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (v)
    (* v (+ 1.1914d0 (* v (+ -0.22533d0 (* v (+ 0.23352d0 (* v (+ -0.020484d0 (* v 0.00081939d0)))))))) 0.01d0)))

(defun munsell-value-to-lstar (v)
  "Converts Munsell value to L*, whose nominal range is [0, 100]."
  (- (* 116d0 (function-f (munsell-value-to-y v))) 16d0))

(defun munsell-value-to-achromatic-xyy (v)
  "Illuminant C."
  (values 0.31006d0 0.31616d0 (munsell-value-to-y v)))

(defun munsell-value-to-achromatic-xyy-from-mrd (v)
  "For devel. Another version of munsell-value-to-achromatic-xyy based
on the Munsell renotation data. V must be integer. It is nearly equal
to munsell-value-to-achromatic-xyy"
  (values 0.31006d0 0.31616d0
	  (clamp (* (aref (vector 0d0 0.0121d0 0.03126d0 0.0655d0 0.120d0 0.1977d0 0.3003d0 0.4306d0 0.591d0 0.7866d0 1.0257d0) v)
		    0.975d0)
		 0d0 1d0)))

(declaim (inline y-to-munsell-value))
(defun y-to-munsell-value (y)
  "Interpolates the inversion table of MUNSELL-VALUE-TO-Y linearly,
whose band width is 10^-3. The
error, (abs (- (y (munsell-value-to-y (y-to-munsell-value y))))), is
smaller than 10^-5."
  (declare (optimize (speed 3) (safety 1)))
  (let* ((y1000 (* (clamp (float y 1d0) 0d0 1d0) 1000))
	 (y1 (floor y1000))
	 (y2 (ceiling y1000)))
    (if (= y1 y2)
	(aref y-to-munsell-value-arr y1)
	(let ((r (- y1000 y1)))
	  (+ (* (- 1 r) (aref y-to-munsell-value-arr y1))
	     (* r (aref y-to-munsell-value-arr y2)))))))

(defun test-value-to-y (&optional (num 100000000))
  "Evaluates error of y-to-munsell-value"
  (declare (optimize (speed 3) (safety 1))
	   (fixnum num))
  (let ((max-error 0d0)
	(worst-y 0d0))
    (dotimes (n num (values max-error worst-y))
      (let* ((y (random 1d0))
	     (delta (abs (- (munsell-value-to-y (y-to-munsell-value y)) y))))
	(when (>= delta max-error)
	  ;;(format t "y=~A delta=~A~%" y delta)
	  (setf worst-y y
		max-error delta))))))

(defun qrgb-to-munsell-value (r g b &optional (rgbspace +srgb+))
  (y-to-munsell-value (nth-value 1 (qrgb-to-xyz r g b rgbspace))))



;;;
;;; Munsell-to- converters
;;; The primary converter is mhvc-to-lchab.
;;;

(declaim (ftype (function * (values (double-float 0d0 360d0) double-float double-float))
		mhvc-to-lchab-all-integer-case
		mhvc-to-lchab-value-chroma-integer-case
		mhvc-to-lchab-value-integer-case
		mhvc-to-lchab-general-case
		mhvc-to-lchab-illum-c))


(declaim (inline mhvc-to-lchab-all-integer-case))
(defun mhvc-to-lchab-all-integer-case (hue40 tmp-value half-chroma &optional (dark nil))
  "All integer case. There are no type checks: e.g. HUE40 must be in
{0, ...., 39}."
  (declare (optimize (speed 3) (safety 0))
	   (fixnum hue40 tmp-value half-chroma))
  (macrolet ((gen-body (arr-l arr-c-h)
               `(if (<= half-chroma 25)
                    (values (aref ,arr-l tmp-value)
                            (aref ,arr-c-h hue40 tmp-value half-chroma 0)
                            (aref ,arr-c-h hue40 tmp-value half-chroma 1))
                    ;; in the case chroma > 50
                    (let ((cstarab (aref ,arr-c-h hue40 tmp-value 25 0))
                          (factor (* half-chroma #.(float 1/25 1d0))))
                      (values (aref ,arr-l tmp-value)
                              (* cstarab factor)
                              (aref ,arr-c-h hue40 tmp-value 25 1))))))
    (if dark
        (gen-body mrd-array-l-dark mrd-array-c-h-dark)
        (gen-body mrd-array-l mrd-array-c-h))))

(declaim (inline mhvc-to-lchab-value-chroma-integer-case))
(defun mhvc-to-lchab-value-chroma-integer-case (hue40 tmp-value half-chroma &optional (dark nil))
  (declare (optimize (speed 3) (safety 0))
	   ((double-float 0d0 40d0) hue40)
	   (fixnum tmp-value half-chroma))
  (let ((hue1 (floor hue40))
        (hue2 (mod (ceiling hue40) 40)))
    (multiple-value-bind (lstar cstarab1 hab1)
        (mhvc-to-lchab-all-integer-case hue1 tmp-value half-chroma dark)
      (if (= hue1 hue2)
          (values lstar cstarab1 hab1)
          (multiple-value-bind (disused cstarab2 hab2)
              (mhvc-to-lchab-all-integer-case hue2 tmp-value half-chroma dark)
            (declare (ignore disused)
                     ((double-float 0d0 360d0) hab1 hab2))
            (if (= hab1 hab2)
                (values lstar cstarab1 hab1)
                (let* ((hab (the (double-float 0d0 360d0)
                                 (circular-lerp (- hue40 hue1) hab1 hab2 360d0)))
                       (cstarab (+ (* cstarab1 (/ (subtract-with-mod hab2 hab 360d0)
                                                  (subtract-with-mod hab2 hab1 360d0)))
                                   (* cstarab2 (/ (subtract-with-mod hab hab1 360d0)
                                                  (subtract-with-mod hab2 hab1 360d0))))))
                  (values lstar cstarab hab))))))))

(defun mhvc-to-lchab-value-integer-case (hue40 tmp-value half-chroma &optional (dark nil))
  (declare (optimize (speed 3) (safety 0))
	   ((double-float 0d0 40d0) hue40)
	   ((double-float 0d0 #.*maximum-chroma*) half-chroma)
	   (fixnum tmp-value))
  (let ((hchroma1 (floor half-chroma))
	(hchroma2 (ceiling half-chroma)))
    (if (= hchroma1 hchroma2)
	(mhvc-to-lchab-value-chroma-integer-case hue40 tmp-value (round half-chroma) dark)
	(multiple-value-bind (lstar astar1 bstar1)
	    (multiple-value-call #'lchab-to-lab
	      (mhvc-to-lchab-value-chroma-integer-case hue40 tmp-value hchroma1 dark))
	  (multiple-value-bind (disused astar2 bstar2)
	      (multiple-value-call #'lchab-to-lab
		(mhvc-to-lchab-value-chroma-integer-case hue40 tmp-value hchroma2 dark))
	    (declare (ignore disused)
		     (double-float lstar astar1 bstar1 astar2 bstar2))
	    (let* ((astar (+ (* astar1 (- hchroma2 half-chroma))
			     (* astar2 (- half-chroma hchroma1))))
		   (bstar (+ (* bstar1 (- hchroma2 half-chroma))
			     (* bstar2 (- half-chroma hchroma1)))))
	      (lab-to-lchab lstar astar bstar)))))))


(defun mhvc-to-lchab-general-case (hue40 tmp-value half-chroma &optional (dark nil))
  (declare (optimize (speed 3) (safety 0))
  	   ((double-float 0d0 40d0) hue40 tmp-value)
  	   ((double-float 0d0 #.*maximum-chroma*) half-chroma))
  (let ((true-value (if dark (* tmp-value 0.2d0) tmp-value)))
    (let  ((tmp-val1 (floor tmp-value))
	   (tmp-val2 (ceiling tmp-value))
	   (lstar (munsell-value-to-lstar true-value)))
      (if (= tmp-val1 tmp-val2)
	  (mhvc-to-lchab-value-integer-case hue40 tmp-val1 half-chroma dark)
	  ;; If the given color is so dark that it is out of MRD, we
	  ;; use the fact that the chroma and hue of LCh(ab)
	  ;; corresponds roughly to that of Munsell.
	  (if (zerop tmp-val1)
	      (multiple-value-bind (disused cstarab hab)
		  (mhvc-to-lchab-value-integer-case hue40 1 half-chroma dark)
		(declare (ignore disused))
		(values lstar cstarab hab))
	      (multiple-value-bind (lstar1 astar1 bstar1)
		  (multiple-value-call #'lchab-to-lab
		    (mhvc-to-lchab-value-integer-case hue40 tmp-val1 half-chroma dark))
		(multiple-value-bind (lstar2 astar2 bstar2)
		    (multiple-value-call #'lchab-to-lab
		      (mhvc-to-lchab-value-integer-case hue40 tmp-val2 half-chroma dark))
		  (declare (double-float lstar
                                         lstar1 astar1 bstar1
                                         lstar2 astar2 bstar2))
		  (let ((astar (+ (* astar1 (/ (- lstar2 lstar) (- lstar2 lstar1)))
				  (* astar2 (/ (- lstar lstar1) (- lstar2 lstar1)))))
			(bstar (+ (* bstar1 (/ (- lstar2 lstar) (- lstar2 lstar1)))
				  (* bstar2 (/ (- lstar lstar1) (- lstar2 lstar1))))))
		    (lab-to-lchab lstar astar bstar)))))))))


(define-condition invalid-mhvc-error (simple-error)
  ((value :initarg :value
	  :initform 0d0
	  :accessor cond-value)
   (chroma :initarg :chroma
	   :initform 0d0
	   :accessor cond-chroma))
  (:report (lambda (condition stream)
	     (format stream "Value and chroma must be within [0, 10] and [0, ~A), respectively: (V C) = (~A ~A)"
		     *maximum-chroma*
		     (cond-value condition)
		     (cond-chroma condition)))))

      
(defun mhvc-out-of-mrd-p (hue40 value chroma)
  "Checks if MHVC is out of the Munsell renotation data."
  (or (< value 0) (> value 10)
      (< chroma 0)
      (> chroma (max-chroma-in-mrd hue40 value))))


(defun mhvc-invalid-p (hue40 value chroma)
  "Checks if MHVC values are out of range."
  (declare (ignore hue40))
  (or (< value 0) (> value 10)
      (< chroma 0) (> chroma *maximum-chroma*)))

(declaim (inline mhvc-to-lchab-illum-c-))
(defun mhvc-to-lchab-illum-c (hue40 value chroma)
  "Illuminant C."
  (declare (optimize (speed 3) (safety 1)))
  (let ((d-hue (mod (float hue40 1d0) 40d0))
	(d-value (clamp (float value 1d0) 0d0 10d0))
	(d-chroma (clamp (float chroma 1d0) 0d0 *maximum-chroma*)))
    ;; (format t "~A ~A ~A" d-hue (* d-value 5) (/ d-chroma 2))
    (if (>= d-value 1d0)
	(mhvc-to-lchab-general-case d-hue d-value (* d-chroma 0.5d0) nil)
	(mhvc-to-lchab-general-case d-hue (* d-value 5d0) (* d-chroma 0.5d0) t))))

(declaim (inline mhvc-to-xyz-illum-c))
(defun mhvc-to-xyz-illum-c (hue40 value chroma)
  "Illuminant C. (Munsell Renotation Data is measured under the
Illuminant C.)"
  (declare (optimize (speed 3) (safety 1)))
  (multiple-value-call #'lchab-to-xyz
    (mhvc-to-lchab-illum-c (float hue40 1d0) (float value 1d0) (float chroma 1d0))
    +illum-c+))

(declaim (inline mhvc-to-xyz))
(defun mhvc-to-xyz (hue40 value chroma)
  "Illuminant D65. It causes an error by Bradford transformation,
since the Munsell Renotation Data is measured under the Illuminant C."
  (declare (optimize (speed 3) (safety 1)))
  (multiple-value-call #'c-to-d65
    (mhvc-to-xyz-illum-c (float hue40 1d0)
			 (float value 1d0)
			 (float chroma 1d0))))

(defun mhvc-to-xyy (hue40 value chroma)
  "Illuminant D65."
  (multiple-value-call #'xyz-to-xyy
    (mhvc-to-xyz hue40 value chroma)))

(defun mhvc-to-lrgb (hue40 value chroma &optional (rgbspace +srgb+))
  "The standard illuminant is D65: that of RGBSPACE must also be D65."
  (multiple-value-call #'xyz-to-lrgb
    (mhvc-to-xyz hue40 value chroma)
    rgbspace))

(declaim (inline mhvc-to-qrgb))
(defun mhvc-to-qrgb (hue40 value chroma &key (rgbspace +srgb+) (clamp nil))
  "The standard illuminant is D65: that of RGBSPACE must also be D65."
  (declare (optimize (speed 3) (safety 1)))
  (multiple-value-call #'xyz-to-qrgb
    (mhvc-to-xyz hue40 value chroma)
    :rgbspace rgbspace
    :clamp clamp))

(defun bench-mhvc-to-qrgb (&optional (num 300000))
  (time-after-gc
    (dotimes (x num)
      (mhvc-to-qrgb (random 40d0) (random 10d0) (random 50d0)))))

(defun bench-mhvc-to-lchab (&optional (num 2000000))
  (time-after-gc
    (dotimes (x num)
      (mhvc-to-lchab-illum-c (random 80d0) (random 10d0) (random 50d0)))))

(define-condition munsellspec-parse-error (parse-error)
  ((spec :initarg :spec
	 :initform nil
	 :accessor cond-spec))
  (:report (lambda (condition stream)
	     (format stream "Invalid Munsell specification: ~A"
		     (cond-spec condition)))))

(defun munsell-to-mhvc (munsellspec)
  "Usage Example:
CL-USER> (dufy:munsell-to-mhvc \"0.02RP 0.9/3.5\")
=> (36.00799999982119d0 0.8999999761581421d0 3.5d0)

Many other notations of numbers are acceptable; an ugly specification
as follows are also available:

CL-USER> (dufy:munsell-to-mhvc \"2d-2RP .9/ #x0ffffff\")
=> (36.008d0 0.8999999761581421d0 1.6777215d7)

but the capital letters and  '/' are reserved:

CL-USER> (dufy:munsell-to-mhvc \"2D-2RP 9/10 / #x0FFFFFF\")
=> ERROR,
"
  (let ((lst (let ((*read-default-float-format* 'double-float))
	       (mapcar (compose (rcurry #'coerce 'double-float)
				#'read-from-string)
		       (remove "" (cl-ppcre:split "[^0-9.a-z\-]+" munsellspec)
			       :test #'string=)))))
    (let* ((hue-name (cl-ppcre:scan-to-strings "[A-Z]+" munsellspec))
	   (hue-number
	    (switch (hue-name :test #'string=)
	      ("R" 0) ("YR" 1) ("Y" 2) ("GY" 3) ("G" 4)
	      ("BG" 5) ("B" 6) ("PB" 7) ("P" 8) ("RP" 9) ("N" -1)
	      (t (error (make-condition 'munsellspec-parse-error
					:spec (format nil "invalid hue designator: ~A" hue-name)))))))
      (if (< hue-number 0)
	  (values 0d0 (car lst) 0d0)
	  (if (/= (length lst) 3)
	      (error (make-condition 'munsellspec-parse-error
				     :spec (format nil "contains more than 3 numbers: ~A" lst)))
	      (progn
		(setf (car lst) (+ (* hue-number 4) (/ (* (car lst) 2) 5)))
		(values-list lst)))))))

(defun mhvc-to-munsell (hue40 value chroma &optional (digits 2))
  (let ((unit (concatenate 'string "~," (write-to-string digits) "F")))
    (if (< chroma (* 0.5d0 (expt 0.1d0 digits))) ; if achromatic
	(format nil (concatenate 'string "N " unit) value)
	(let* ((hue40$ (mod hue40 40d0))
	       (hue-number (floor (/ hue40$ 4)))
	       (hue-prefix (* (mod hue40$ 4) 2.5d0))
	       (hue-name (aref #("R" "YR" "Y" "GY" "G"
				 "BG" "B" "PB" "P" "RP")
			       hue-number)))
	  (format nil (concatenate 'string unit "~A " unit "/" unit)
		  hue-prefix hue-name value chroma)))))



(defun munsell-out-of-mrd-p (munsellspec)
  (multiple-value-call #'mhvc-out-of-mrd-p (munsell-to-mhvc munsellspec)))

(defun munsell-to-lchab-illum-c (munsellspec)
  "Illuminant C."
  (multiple-value-bind (hue40 value chroma) (munsell-to-mhvc munsellspec)
    (if (mhvc-invalid-p hue40 value chroma)
	(error (make-condition 'invalid-mhvc-error :value value :chroma chroma))
	(mhvc-to-lchab-illum-c hue40 value chroma))))

(defun munsell-to-xyz (munsellspec)
  "Illuminant D65."
  (multiple-value-bind (hue40 value chroma) (munsell-to-mhvc munsellspec)
    (if (mhvc-invalid-p hue40 value chroma)
	(error (make-condition 'invalid-mhvc-error :value value :chroma chroma))
	(mhvc-to-xyz hue40 value chroma))))

(defun munsell-to-xyz-illum-c (munsellspec)
  (multiple-value-bind (hue40 value chroma) (munsell-to-mhvc munsellspec)
    (if (mhvc-invalid-p hue40 value chroma)
	(error (make-condition 'invalid-mhvc-error :value value :chroma chroma))
	(mhvc-to-xyz-illum-c hue40 value chroma))))

(defun munsell-to-xyy (munsellspec)
  "Illuminant D65."
  (multiple-value-call #'xyz-to-xyy (munsell-to-xyz munsellspec)))


(defun munsell-to-qrgb (munsellspec &key (rgbspace +srgb+) (clamp nil))
  "Illuminant D65; the standard illuminant of RGBSPACE must also be D65."
  (multiple-value-call #'xyz-to-qrgb
    (munsell-to-xyz munsellspec)
    :rgbspace rgbspace
    :clamp clamp))


(defun max-chroma-lchab (hue40 value &key (use-dark t))
  "Returns the LCh(ab) value of the color on the max-chroma boundary in MRD."
  (mhvc-to-lchab-illum-c hue40
                         value
                         (max-chroma-in-mrd hue40 value :use-dark use-dark)))


;;;
;;; -to-Munsell converters
;;;

(declaim (inline lstar-to-munsell-value))
(defun lstar-to-munsell-value (lstar)
  (declare (optimize (speed 3) (safety 1)))
  (y-to-munsell-value (lstar-to-y (float lstar 1d0))))

(defun rough-lchab-to-mhvc (lstar cstarab hab)
  "rough conversion from LCHab to munsell HVC"
  (declare (optimize (speed 3) (safety 0))
	   (double-float lstar cstarab hab))
  (values (* hab #.(float 40/360 1d0))
	  (lstar-to-munsell-value lstar)
	  (* cstarab #.(/ 5.5d0))))

(declaim (ftype (function * (values double-float &optional)) circular-delta))
(defun circular-delta (theta1 theta2)
  "used in INVERT-LCHAB-TO-MHVC"
  (declare (optimize (speed 3) (safety 0))
	   (double-float theta1 theta2))
  (let ((z (mod (- theta1 theta2) 360d0)))
    (if (<= z 180)
	z
	(- z 360d0))))

(define-condition large-approximation-error (arithmetic-error)
  ((message :initarg :message
            :initform "Couldn't achieve the sufficent accuracy."
            :accessor cond-message))
  (:report (lambda (condition stream)
	     (format stream "~A"
                     (cond-message condition)))))

;; used in INVERT-LCHAB-TO-MHVC
(declaim (inline invert-mhvc-to-lchab))
(defun invert-mhvc-to-lchab (lstar cstarab hab init-hue40 init-chroma &key (max-iteration 200) (if-reach-max :error) (factor 0.5d0) (threshold 1d-6))
  "Illuminant C."
  (declare (optimize (speed 3) (safety 0))
	   (double-float lstar cstarab hab factor threshold)
	   (fixnum max-iteration))
  (let ((tmp-hue40 init-hue40)
	(v (lstar-to-munsell-value lstar))
	(tmp-c init-chroma))
    (declare (double-float tmp-hue40 tmp-c v))
    (dotimes (i max-iteration)
      (multiple-value-bind (disused tmp-cstarab tmp-hab)
	  (mhvc-to-lchab-illum-c tmp-hue40 v tmp-c)
	(declare (ignore disused))
	(let* ((delta-cstarab (- cstarab tmp-cstarab))
	       (delta-hab (circular-delta hab tmp-hab))
	       (delta-hue40 (* delta-hab #.(float 40/360 1d0)))
	       (delta-c (* delta-cstarab #.(/ 5.5d0))))
	  (if (and (<= (abs delta-hue40) threshold)
		   (<= (abs delta-c) threshold))
	      (return-from invert-mhvc-to-lchab
                (values (mod tmp-hue40 40d0) v tmp-c))
	      (setf tmp-hue40 (+ tmp-hue40
                                 (* factor delta-hue40))
		    tmp-c (max 0d0 (+ tmp-c
                                      (* factor delta-c))))))))
    (ecase if-reach-max
      (:error
       (error (make-condition 'large-approximation-error
                              :message "INVERT-MHVC-TO-LCHAB reached MAX-ITERATION without achieving sufficient accuracy.")))
      (:negative (values most-negative-double-float
                         most-negative-double-float
                         most-negative-double-float))
      (:return (values (mod tmp-hue40 40d0) v tmp-c)))))


(defun lchab-to-mhvc-illum-c (lstar cstarab hab &key (max-iteration 200) (if-reach-max :error) (factor 0.5d0) (threshold 1d-6))
  "An inverter of MHVC-TO-LCHAB-ILLUM-C with a simple iteration
algorithm like the one in \"An Open-Source Inversion Algorithm for the
Munsell Renotation\" by Paul Centore, 2011:

V := LSTAR-TO-MUNSELL-VALUE(L*);
C_0 := C*ab / 5.5;
H_0 := Hab / 9;
C_(n+1) :=  C_n + factor * delta(C_n);
H_(n+1) := H_n + factor * delta(H_n),

where delta(H_n) and delta(C_n) is internally calculated at every
step. It returns Munsell HVC values if C_0 <= THRESHOLD or
max(delta(H_n), delta(C_n)) falls below THRESHOLD.

IF-REACH-MAX specifies the action to be taken if the loop reaches the
MAX-ITERATION:
:error: Error of type DUFY:LARGE-APPROXIMATION-ERROR is signaled.
:negative: Three MOST-NEGATIVE-DOUBLE-FLOATs are returned.
:return: Just returns HVC as it is.
"
  (declare (optimize (speed 3) (safety 1))
	   (fixnum max-iteration))
  (with-double-float (lstar cstarab hab factor threshold)
    (let ((init-h (* hab #.(float 40/360 1d0)))
	  (init-c (* cstarab #.(/ 5.5d0))))
      (if (<= init-c threshold) ; returns the initial HVC, if achromatic
          (values init-h
                  (lstar-to-munsell-value lstar)
                  init-c)
          (invert-mhvc-to-lchab lstar cstarab hab
                                init-h init-c
                                :max-iteration max-iteration
                                :if-reach-max if-reach-max
                                :factor factor
                                :threshold threshold)))))

(defun lchab-to-munsell-illum-c (lstar cstarab hab &key (max-iteration 200) (if-reach-max :error) (factor 0.5d0) (threshold 1d-6) (digits 2))
  "Illuminant C."
  (multiple-value-bind (h v c)
      (lchab-to-mhvc-illum-c lstar cstarab hab
                             :max-iteration max-iteration
                             :if-reach-max if-reach-max
                             :factor factor
                             :threshold threshold)
    (values (mhvc-to-munsell h v c digits))))

(defun xyz-to-mhvc (x y z &key (max-iteration 200) (if-reach-max :error) (factor 0.5d0) (threshold 1d-6))
  "Illuminant D65. doing Bradford transformation."
  (multiple-value-call #'lchab-to-mhvc-illum-c
    (multiple-value-call #'xyz-to-lchab
      (d65-to-c x y z)
      +illum-c+)
    :max-iteration max-iteration
    :if-reach-max if-reach-max
    :factor factor
    :threshold threshold))


(defun xyz-to-munsell (x y z &key (max-iteration 200) (if-reach-max :error) (factor 0.5d0) (threshold 1d-6) (digits 2))
  "Illuminant D65. doing Bradford transformation."
  (multiple-value-bind (m h v)
      (xyz-to-mhvc x y z
		   :max-iteration max-iteration
                   :if-reach-max if-reach-max
		   :factor factor
		   :threshold threshold)
    (values (mhvc-to-munsell m h v digits))))

  
(defun test-inverter ()
  "For devel."
  (let ((max-iteration 300))
    (do ((lstar 0 (+ lstar 10)))
	((> lstar 100) 'done)
      (do ((hab 0 (+ hab 9)))
	  ((= hab 360))
	(do ((cstarab 0 (+ cstarab 10)))
	    ((= cstarab 200) nil)
	  (multiple-value-bind (lst number)
	      (lchab-to-mhvc-illum-c lstar cstarab hab
                                     :threshold 1d-6
                                     :max-iteration max-iteration)
	    (declare (ignore lst))
	    (when (= number max-iteration)
	      (format t "failed at L*=~A C*ab=~A Hab=~A.~%" lstar cstarab hab))))))))

(defun test-inverter2 (&optional (num-loop 10000) (profile nil) (rgbspace +srgb+))
  "For devel."
  #+sbcl(when profile (sb-profile:profile "DUFY"))
  #-sbcl(declare (ignore profile))
  (let ((qmax+1 (1+ (rgbspace-qmax rgbspace)))
	(cat-func (gen-cat-function (rgbspace-illuminant rgbspace) +illum-c+))
	(sum 0))
    (dotimes (x num-loop (prog1 (float (/ sum num-loop) 1d0)
			   #+sbcl(when profile
				   (sb-profile:report :print-no-call-list nil)
				   (sb-profile:unprofile "DUFY"))))
      (let ((qr (random qmax+1))
            (qg (random qmax+1))
            (qb (random qmax+1)))
	(multiple-value-bind (lstar cstarab hab)
	    (multiple-value-call #'xyz-to-lchab
	      (multiple-value-call cat-func
		(qrgb-to-xyz qr qg qb rgbspace))
	      +illum-c+)
	  (let ((result (lchab-to-mhvc-illum-c lstar cstarab hab
                                               :max-iteration 300
                                               :if-reach-max :negative
                                               :factor 0.5d0)))
            (when (= result most-negative-double-float)
	      (incf sum)
	      (format t "~A ~A ~A, (~a ~a ~a)~%" lstar cstarab hab qr qg qb))))))))

;; doesn't converge:
;; LCH = 90.25015693115249d0 194.95626408656423d0 115.6958104971207d0
;; (38754 63266 343) in ProPhoto, 16-bit

(defun test-inverter3 (&optional (rgbspace +srgb+))
  "For devel."
  (declare (optimize (speed 3) (safety 1)))
  (let ((sum 0))
    (dotimes (qr 256)
      (print qr)
      (dotimes (qg 256)
	(dotimes (qb 256)
	  (let ((result (multiple-value-call #'xyz-to-mhvc 
                          (qrgb-to-xyz qr qg qb rgbspace)
                          :if-reach-max :negative
                          :max-iteration 200
                          :threshold 1.0d-3)))
	    (when (= result most-negative-double-float)
	      (incf sum)
	      (format t "(~a ~a ~a)~%" qr qg qb))))))
    (float (/ sum (* 256 256 256)) 1d0)))
