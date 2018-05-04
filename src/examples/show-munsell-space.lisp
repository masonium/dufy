(in-package :dufy.examples)

(deftype uint nil '(integer 0 #.(expt 10 9)))
(deftype sint nil '(integer #.(- (expt 10 9)) #.(expt 10 9)))

(defun draw-srgb-in-munsell (&optional (size 300) (framerate 10) (bg-color sdl:*black*))
  "Graphical demonstration with SDL. Renders the sRGB space in the
Munsell space."
  (declare (optimize (speed 3) (safety 1))
           (type uint size framerate))
  (let* ((value100 0)
         (radius (round (/ size 2)))
         (center-x radius)
         (center-y radius)
         (max-chroma 30d0)
         (line-col (sdl:color :r 255 :g 255 :b 255 :a 128)))
    (labels ((polar (i j)
               (declare (type sint i j))
               (let ((delta-x (- j center-x))
                     (delta-y (- i center-y)))
                 (declare (type sint delta-x delta-y))
                 (values (sqrt (+ (* delta-y delta-y)
                                  (* delta-x delta-x)))
                         (atan delta-y delta-x))))
             (coord-to-mhvc (i j)
               (multiple-value-bind (r theta) (polar i j)
                 (values (- 20 (* theta #.(/ 40 dufy.core::two-pi)))
                         (* value100 0.1d0)
                         (* max-chroma (/ r radius))))))
      (declare (inline coord-to-mhvc polar))
      (declare (type uint value100 radius center-x center-y))
      (sdl:with-init ()
        (sdl:window size size
                    :bpp 32
                    :title-caption "sRGB in Munsell space")
        (sdl:initialise-default-font sdl:*font-10x20*)
        (sdl:clear-display bg-color)
        (setf (sdl:frame-rate) framerate)
        (sdl:with-events ()
          (:quit-event () t)
          (:key-down-event ()
                           (sdl:push-quit-event))
          (:mouse-button-down-event (:x j :y i)
                                    (format t "(H V C) = ~A~%"
                                            (multiple-value-list (coord-to-mhvc i j))))
          (:idle ()
                 (when (<= value100 100)
                   (sdl:clear-display bg-color)
                   (dotimes (i size)
                     (dotimes (j size)
                       (multiple-value-bind (qr qg qb)
                           (multiple-value-call #'dufy:mhvc-to-qrgb
                             (coord-to-mhvc i j)
                             :clamp nil)
                         (declare (type sint qr qg qb))
                         (when (and (<= 0 qr 255)
                                    (<= 0 qg 255)
                                    (<= 0 qb 255))
                           (sdl:draw-pixel-* i j
                                             :color (sdl:color :r qr :g qg :b qb :a 0))))))
                   (sdl:draw-vline center-x 0 size :color line-col)
                   (sdl:draw-hline 0 size center-y :color line-col)
                   (sdl:draw-string-solid (format nil "V=~,2F" (* value100 0.1d0))
                                          (sdl:point :x 10 :y 10))
                   (sdl:update-display)
                   (incf value100))))))))
