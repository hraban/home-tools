#!/usr/bin/env sbcl --script

;; Copyright © 2023  Hraban Luyat
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, version 3 of the License.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.
;;
;; You should have received a copy of the GNU Affero General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; A silly utility script I wrote because my phone broke. Mostly just for
;; dogfooding purposes.

(require "asdf")
(require "uiop")

(asdf:load-system "arrow-macros")
(asdf:load-system "f-underscore")
(asdf:load-system "inferior-shell")
(asdf:load-system "local-time")
(asdf:load-system "trivia")
(asdf:load-system "trivia.ppcre")

(defpackage #:alarm
  (:use #:cl #:arrow-macros #:local-time)
  (:import-from #:trivia.ppcre
                #:ppcre)
  (:import-from #:f-underscore
                #:_ #:f_)
  (:shadowing-import-from #:trivia
                          #:match)
  (:local-nicknames (#:alex #:alexandria)
                    (#:sh #:inferior-shell)))

(in-package #:alarm)

(defvar *now*)
(defvar *default-msg* "wake up")

(defun sh (&rest args)
  (apply #'sh:run `(,@args :show ,(uiop:getenv "DEBUGSH"))))

(defun println (s)
  (declare (type string s))
  (format T "~A~%" s))

(defgeneric say (msg))

(defmethod say ((msg string))
  (sh `(say "--" ,msg)))

(defmethod say ((msg list))
  (say (format NIL "~{~A~^ ~}" msg)))

;;; Proxy functions because local-time::adjust-time is a macro for some reason
(defgeneric timezone-set (time unit val))
(defmethod timezone-set (time (unit (eql :hour)) val)
  (adjust-timestamp time
    (set :hour val)))
(defmethod timezone-set (time (unit (eql :minute)) val)
  (adjust-timestamp time
    (set :minute val)))
(defmethod timezone-set (time (unit (eql :sec)) val)
  (adjust-timestamp time
    (set :sec val)))

(defun zip (&rest lists)
  (apply #'mapcar #'list lists))

(defun index-hms (hms)
  (-<> hms
       (zip <> '(:hour :minute :sec))
       (remove nil <> :key #'car)))

(defun sleep-msg (hms)
  (some->> hms
           index-hms
           (format NIL "Sleeping for ~{~{~A ~(~A~)~:*~:P~*~}~^, ~}")))

(defun sec->hms (total-seconds)
  (multiple-value-bind (rest sec) (floor total-seconds 60)
    (multiple-value-bind (hour minute) (floor rest 60)
      (substitute nil 0 (list hour minute sec)))))

(defun set-alarm-seconds (sec msg)
  (let ((sleep-msg (-> sec
                       sec->hms
                       sleep-msg)))
    (format T "~A at " sleep-msg)
    (finish-output)
    (sh '(date))
    ;; Make sure this shows up last, to grab attention
    (println "Can you hear me?")
    (say sleep-msg))
  (say "Is Amphetamine turned on, and for long enough?")
  (sleep sec)
  (format T "Waking up at ")
  (finish-output)
  (sh '(date))
  ;; Alarm! Loop until killed.
  (loop do (progn (say msg) (sleep 3))))

(defgeneric set-alarm (in-or-at hms msg))

(defmethod set-alarm ((in-or-at (eql 'in)) hms msg)
  (destructuring-bind (h m s) (mapcar (f_ (or _ 0)) hms)
    (-> h
        (* 60)
        (+ m)
        (* 60)
        (+ s)
        (set-alarm-seconds msg))))

(defun set-hms (hms)
  (reduce (lambda (acc el)
            (destructuring-bind (val unit) el
              (timezone-set acc unit val)))
          hms
          :initial-value *now*))

(defun ensure-future (init)
  "If this is in the past, add 1 day to it"
  (if (timestamp>= init *now*)
      init
      (adjust-timestamp init
        (offset :day 1))))

(defun diff-in-seconds (time)
  (- (timestamp-to-universal time)
     (timestamp-to-universal *now*)))

(defmethod set-alarm ((in-or-at (eql 'at)) hms msg)
  (some-> hms
          index-hms
          set-hms
          ensure-future
          diff-in-seconds
          (set-alarm-seconds msg)))


;;; CLI

(defun print-usage ()
  (println "Usage: alarm <at|in> TIME [MSG...]

Examples:

    alarm at 3h     # set an alarm for the next 3 AM
    alarm at 15h    # set an alarm for the next 3 PM
    alarm at 4h3m2s # set an alarm for the next 4:03:02 AM
    alarm in 3h     # set a timer for 180 minutes
    alarm in 1s     # set a timer for 1 second
    alarm in 4h3m2s # set a timer for 4 hours, 3 minutes, 2 seconds

    alarm in 1h chicken done # Set a timer with custom message
"))

(defun parse-integer-or-nil (s)
  (declare (type (or null string) s))
  (some-> s parse-integer))

(defun main ()
  (let ((args (uiop:command-line-arguments))
        ;; Set one to avoid racing
        (*now* (now)))
    (if (intersection args '("-h" "--help") :test #'equal)
        (progn
          (print-usage)
          (uiop:quit 0))
        (match args
          ((trivia:guard
            (list* "in" (ppcre "^(?:(\\d+)h)?(?:(\\d+)m(?:in)?)?(?:(\\d+)s(?:ec)?)?$" h m s) msg)
            (some #'identity (list h m s)))
           (set-alarm 'in (mapcar #'parse-integer-or-nil (list h m s)) (or msg *default-msg*)))
          ((list* "at" (ppcre "^(\\d+)(?:[h:](?:(\\d+)m(?:in)??)?)?" h m) msg)
           (set-alarm 'at (mapcar #'parse-integer-or-nil (list h m "0")) (or msg *default-msg*)))
          (_
           (print-usage)
           (uiop:quit 1))))))

(main)
