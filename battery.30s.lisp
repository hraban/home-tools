#!/usr/bin/env sbcl --script
;; <xbar.title>Mac Battery Control</xbar.title>
;; <xbar.author>Hraban Luyat</xbar.author>
;; <xbar.author.github>hraban</xbar.author.github>
;; <xbar.desc>Control your Mac laptop’s maximum battery charge to improve its longevity</xbar.desc>
;; <xbar.var>boolean(DEBUG=false): Verbose output</xbar.var>
;; <xbar.dependencies>lisp</xbar.dependencies>

;; Copyright © 2023–2024  Hraban Luyat
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

(setf *compile-verbose* NIL)
(setf *trace-output* *error-output*)

(require "asdf")
(require "uiop")

(asdf:load-system "arrow-macros")
(asdf:load-system "cl-interpol")
(asdf:load-system "cl-json")
(asdf:load-system "inferior-shell")

(defpackage #:battery
  (:use #:cl #:arrow-macros)
  (:local-nicknames (#:sh #:inferior-shell)))

(in-package #:battery)

(named-readtables:in-readtable :interpol-syntax)

(defvar *bclm* "@bclm@")
;; This really only works because we are in Nix. How else you gonna do it? UIOP
;; doesn’t give you access when calling a file using --script.
(defvar *me* "@self@")

(defun debugp ()
  (string= "true" (uiop:getenv "DEBUG")))

(defun sh (&rest args)
  (apply #'sh:run `(,@args :show ,(debugp))))

(defun sh/ss (&rest args)
  (apply #'sh `(,@args :output (:string :stripped t))))

(defun bclm-read ()
  (parse-integer (sh/ss `(,*bclm* read))))

(defun bclm-write (val)
  (sh `(sudo ,*bclm* write ,val)))

(defun println (s)
  (format T "~A~%" s))

(defun boolstr (b)
  (if b "true" "false"))

(defun print-set (lvl)
  (println #?"Set to ${lvl} | shell=${*me*} | param1=${lvl} | terminal=${(boolstr (debugp))} | refresh=true"))

(defun print-menu ()
  (println (bclm-read))
  (println "---")
  (dolist (n (loop for i from 50 upto 100 by 10 collect i))
    (print-set n)))

(defun main ()
  (trivia:match (uiop:command-line-arguments)
    (()
     (print-menu))
    ((list x)
     (bclm-write x)
     (print-menu))))

(main)
