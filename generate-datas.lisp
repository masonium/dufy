;;; This is a script file which generates fundamental data and saves them as a .lisp file.

(require :alexandria)

(defparameter data-filename "fundamental-data.lisp")
(defparameter data-pathname (merge-pathnames data-filename *load-pathname*))


(defparameter color-matching-arr-1931
  (make-array '(471 3) :element-type 'double-float :initial-element 0d0))
(defparameter color-matching-arr-1964
  (make-array '(471 3) :element-type 'double-float :initial-element 0d0))

(defun fill-color-matching-arr (arr csv-path)
  (with-open-file (in
		   csv-path
					;(merge-pathnames #P"cie1931-color-matching.csv" *load-pathname*)
		   :direction :input)
    (let ((*read-default-float-format* 'double-float)
	  (tmp-arr
	   (make-array '(95 3) :element-type 'double-float :initial-element 0d0)))
      (dotimes (idx-by5 95)
	(read in)
	(dotimes (coord 3)
	  (setf (aref tmp-arr idx-by5 coord)
		(coerce (read in) 'double-float))))
      (print tmp-arr)
      (dotimes (idx-by1 471)
	(let ((rem (/ (mod idx-by1 5) 5d0))
	      (idx-by5 (floor (/ idx-by1 5))))
	  (dotimes (coord 3)
	    (setf (aref arr idx-by1 coord)
		  (if (= rem 0)
		      (aref tmp-arr idx-by5 coord)
		      (alexandria:lerp rem
				       (aref tmp-arr idx-by5 coord)
				       (aref tmp-arr (1+ idx-by5) coord))))))))))
		
	

(fill-color-matching-arr color-matching-arr-1931 (merge-pathnames #P"cie1931-color-matching.csv" *load-pathname*))
(fill-color-matching-arr color-matching-arr-1964 (merge-pathnames #P"cie1964-color-matching.csv" *load-pathname*))

;; convert munsell value to Y in [0, 1]
(defun munsell-value-to-y (v)
  (* v (+ 1.1914d0 (* v (+ -0.22533d0 (* v (+ 0.23352d0 (* v (+ -0.020484d0 (* v 0.00081939d0)))))))) 0.01d0))

(defun root-finding (func rhs a b threshold)
  (let* ((mid (* 0.5d0 (+ a b)))
	 (lhs (funcall func mid))
	 (delta (abs (- lhs rhs))))
    (if (<= delta threshold)
	mid
	(if (> lhs rhs)
	    (root-finding func rhs a mid threshold)
	    (root-finding func rhs mid b threshold)))))

(defparameter y-to-munsell-value-arr (make-array 1001 :element-type 'double-float :initial-element 0.0d0))

(setf (aref y-to-munsell-value-arr 0) 0.0d0)
(setf (aref y-to-munsell-value-arr 1000) 10.0d0)
(loop for y from 1 to 999 do
  (setf (aref y-to-munsell-value-arr y)
	(root-finding #'munsell-value-to-y (* y 0.001d0) 0 10 1.0d-6)))

;; y should be in [0,1]
(defun y-to-munsell-value (y)
  (let* ((y1000 (* (alexandria:clamp y 0 1) 1000))
	 (y1 (floor y1000))
	 (y2 (ceiling y1000)))
    (if (= y1 y2)
	(aref y-to-munsell-value-arr y1)
	(let ((r (- y1000 y1)))
	  (+ (* (- 1 r) (aref y-to-munsell-value-arr y1))
	     (* r (aref y-to-munsell-value-arr y2)))))))



(defun array-to-list (array)
  (let* ((dimensions (array-dimensions array))
         (depth      (1- (length dimensions)))
         (indices    (make-list (1+ depth) :initial-element 0)))
    (labels ((recurse (n)
               (loop for j below (nth n dimensions)
                     do (setf (nth n indices) j)
                     collect (if (= n depth)
                                 (apply #'aref array indices)
                               (recurse (1+ n))))))
      (recurse 0))))

(defun print-make-array (var-name array &optional (stream t))
  (let ((typ (array-element-type array))
	(dims (array-dimensions array)))
    (format stream "(defparameter ~a ~% #." var-name)
    (prin1 `(make-array (quote ,dims)
			:element-type (quote ,typ)
			:initial-contents (quote ,(array-to-list array)))
	   stream)
    (princ ")" stream)
    (terpri stream)))


(with-open-file (out data-pathname
		     :direction :output
		     :if-exists :supersede)
  (format out ";;; This file is automatically generated by ~a.~%~%"
	  (file-namestring *load-pathname*))
  (format out "(in-package :dufy)~%~%")
  (print-make-array "color-matching-arr-1931" color-matching-arr-1931 out)
  (print-make-array "color-matching-arr-1964" color-matching-arr-1964 out)
  (print-make-array "y-to-munsell-value-arr" y-to-munsell-value-arr out))

(format t "The file is saved at ~A~%" data-pathname)
