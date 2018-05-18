;;;
;;; L*a*b*
;;;

(in-package :dufy-core)

(define-colorspace lab ((lstar double-float)
                        (astar double-float)
                        (bstar double-float)))
(define-colorspace lchab ((lstar double-float)
                          (cstarab double-float)
                          (hab double-float)))
(define-colorspace luv ((lstar double-float)
                        (ustar double-float)
                        (vstar double-float)))
(define-colorspace lchuv ((lstar double-float)
                          (cstaruv double-float)
                          (huv double-float)))

(declaim (inline function-f)
	 (ftype (function * double-float) function-f))
(defun function-f (x)
  (declare (optimize (speed 3) (safety 0))
	   (double-float x))
  (if (> x #.(float 216/24389 1d0))
      (expt x #.(float 1/3 1d0))
      (+ (* #.(/ 24389/27 116d0) x) #.(float 16/116 1d0))))

(define-primary-converter xyz lab (&key (illuminant +illum-d65+))
  (declare (optimize (speed 3) (safety 1)))
  (let ((fx (function-f (/ (float x 1d0) (illuminant-x illuminant))))
	(fy (function-f (float y 1d0)))
	(fz (function-f (/ (float z 1d0) (illuminant-z illuminant)))))
    (values (- (* 116d0 fy) 16d0)
	    (* 500d0 (- fx fy))
	    (* 200d0 (- fy fz)))))

(defconverter xyy lab)
;; (define-primary-converter xyy lab (&key (illuminant +illum-d65+))
;;   (multiple-value-bind (new-x new-y new-z) (xyy-to-xyz small-x small-y y)
;;     (xyz-to-lab new-x new-y new-z illuminant)))

(define-primary-converter lab xyz (&key (illuminant +illum-d65+))
  (declare (optimize (speed 3) (safety 1)))
  (let* ((fy (* (+ (float lstar 1d0) 16d0) 1/116))
	 (fx (+ fy (* (float astar 1d0) 0.002d0)))
	 (fz (- fy (* (float bstar 1d0) 0.005d0))))
    (values (if (> fx #.(float 6/29 1d0))
		(* (illuminant-x illuminant) fx fx fx)
		(* (- fx 16/116) #.(* 3d0 6/29 6/29) (illuminant-x illuminant)))
	    (if (> fy #.(float 6/29 1d0))
		(* fy fy fy)
		(* (- fy 16/116) #.(* 3d0 6/29 6/29)))
	    (if (> fz #.(float 6/29 1d0))
		(* (illuminant-z illuminant) fz fz fz)
		(* (- fz 16/116) #.(* 3d0 6/29 6/29) (illuminant-z illuminant))))))

(declaim (inline lstar-to-y))
(defun lstar-to-y (lstar)
  (declare (optimize (speed 3) (safety 1)))
  (let* ((fy (* (+ (float lstar 1d0) 16d0) 1/116)))
    (if (> fy #.(float 6/29 1d0))
	(* fy fy fy)
	(* (- fy 16/116) #.(* 3d0 6/29 6/29)))))

(declaim (inline y-to-lstar))
(defun y-to-lstar (y)
  (declare (optimize (speed 3) (safety 1)))
  (- (* 116d0 (function-f (float y 1d0))) 16d0))

(defconverter lab xyy)
;; (defun lab-to-xyy (lstar astar bstar &optional (illuminant +illum-d65+))
;;   (multiple-value-call #'xyz-to-xyy
;;     (lab-to-xyz lstar astar bstar illuminant)))

(define-constant +TWO-PI/360+ (/ TWO-PI 360))
(define-constant +360/TWO-PI+ (/ 360 TWO-PI))

(define-primary-converter lab lchab ()
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (astar bstar)
    (values lstar
	    (sqrt (+ (* astar astar) (* bstar bstar)))
	    (mod (* (atan bstar astar) +360/TWO-PI+) 360d0))))

(define-primary-converter lchab lab ()
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (cstarab hab)
    (let ((hue-two-pi (* hab +TWO-PI/360+)))
      (values lstar
	      (* cstarab (cos hue-two-pi))
	      (* cstarab (sin hue-two-pi))))))

(defconverter xyz lchab)
;; (declaim (inline xyz-to-lchab))
;; (defun xyz-to-lchab (x y z &optional (illuminant +illum-d65+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'lab-to-lchab
;;     (xyz-to-lab (float x 1d0) (float y 1d0) (float z 1d0) illuminant)))

(defconverter xyy lchab)
;; (defun xyy-to-lchab (small-x small-y y &optional (illuminant +illum-d65+))
;;   (multiple-value-call #'lab-to-lchab (xyy-to-lab small-x small-y y illuminant)))

(defconverter lchab xyz)
;; (declaim (inline lchab-to-xyz))
;; (defun lchab-to-xyz (lstar cstarab hab &optional (illuminant +illum-d65+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'lab-to-xyz
;;       (lchab-to-lab (float lstar 1d0) (float cstarab 1d0) (float hab 1d0))
;;       illuminant))

(defconverter lchab xyy)
;; (defun lchab-to-xyy (lstar cstarab hab &optional (illuminant +illum-d65+))
;;   (multiple-value-call #'xyz-to-xyy
;;     (lchab-to-xyz lstar cstarab hab illuminant)) )



;;;
;;; L*u*v*
;;;

(declaim (inline calc-uvprime))
(defun calc-uvprime (x y)
  (declare (optimize (speed 3) (safety 0))
	   (double-float x y))
  (let ((denom (+ (* -2d0 x) (* 12d0 y) 3d0)))
    (values (/ (* 4d0 x) denom)
	    (/ (* 9d0 y) denom))))

(declaim (inline calc-uvprime-from-xyz))
(defun calc-uvprime-from-xyz (x y z)
  (declare (optimize (speed 3) (safety 0))
	   (double-float x y z))
  (let ((denom (+ x (* 15d0 y) (* 3d0 z))))
    (values (/ (* 4d0 x) denom)
	    (/ (* 9d0 y) denom))))

(define-primary-converter xyz luv (&key (illuminant +illum-d65+))
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (x y z)
    (multiple-value-bind (uprime vprime)
	(calc-uvprime-from-xyz x y z)
      (multiple-value-bind (urprime vrprime)
	  (calc-uvprime-from-xyz (illuminant-x illuminant)
                                 1d0
                                 (illuminant-z illuminant))
	(let ((lstar (if (> y #.(expt 6/29 3d0))
                         (- (* 116d0 (expt y #.(float 1/3 1d0))) 16d0)
                         (* #.(expt 29/3 3d0) y))))
	  (values lstar
		  (* 13d0 lstar (- uprime urprime))
		  (* 13d0 lstar (- vprime vrprime))))))))

(define-primary-converter luv xyz (&key (illuminant +illum-d65+))
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (lstar ustar vstar)
    (multiple-value-bind (urprime vrprime)
        (calc-uvprime-from-xyz (illuminant-x illuminant)
                               1d0
                               (illuminant-z illuminant))
      (let* ((uprime (+ (/ ustar (* 13d0 lstar)) urprime))
	     (vprime (+ (/ vstar (* 13d0 lstar)) vrprime))
	     (l (/ (+ lstar 16d0) 116d0))
	     (y (if (<= lstar 8d0)
		    (* lstar
                       (expt 3/29 3d0))
		    (* (* l l l)))))
	(values (* y (/ (* 9d0 uprime) (* 4d0 vprime)))
		y
		(* y (/ (- 12d0 (* 3d0 uprime) (* 20d0 vprime)) (* 4d0 vprime))))))))

(define-primary-converter luv lchuv ()
  (declare (optimize (speed 3) (safety 1)))
  (with-double-float (lstar ustar vstar)
    (values lstar
	    (sqrt (+ (* ustar ustar) (* vstar vstar)))
	    (mod (* (atan vstar ustar) +360/TWO-PI+) 360d0))))

(define-primary-converter lchuv luv ()
  (declare (optimize (speed 3) (safety 1)))
  (let ((cstaruv (float cstaruv 1d0)))
    (let ((hue-two-pi (* (float huv 1d0) +TWO-PI/360+)))
      (values lstar
	      (* cstaruv (cos hue-two-pi))
	      (* cstaruv (sin hue-two-pi))))))

(defconverter xyz lchuv)
;; (declaim (inline xyz-to-lchuv))
;; (defun xyz-to-lchuv (x y z &optional (illuminant +illum-d65+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'luv-to-lchuv
;;     (xyz-to-luv x y z illuminant)))

(defconverter lchuv xyz)
;; (declaim (inline lchuv-to-xyz))
;; (defun lchuv-to-xyz (lstar cstaruv huv &optional (illuminant +illum-d65+))
;;   (declare (optimize (speed 3) (safety 1)))
;;   (multiple-value-call #'luv-to-xyz
;;     (lchuv-to-luv (float lstar 1d0) (float cstaruv 1d0) (float huv 1d0))
;;     illuminant))

