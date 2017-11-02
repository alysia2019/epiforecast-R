## author_header begin
## Copyright (C) 2017 Logan C. Brooks
##
## This file is part of epiforecast.  Algorithms included in epiforecast were developed by Logan C. Brooks, David C. Farrow, Sangwon Hyun, Shannon Gallagher, Ryan J. Tibshirani, Roni Rosenfeld, and Rob Tibshirani (Stanford University), members of the Delphi group at Carnegie Mellon University.
##
## Research reported in this publication was supported by the National Institute Of General Medical Sciences of the National Institutes of Health under Award Number U54 GM088491. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health. This material is based upon work supported by the National Science Foundation Graduate Research Fellowship Program under Grant No. DGE-1252522. Any opinions, findings, and conclusions or recommendations expressed in this material are those of the authors and do not necessarily reflect the views of the National Science Foundation. David C. Farrow was a predoctoral trainee supported by NIH T32 training grant T32 EB009403 as part of the HHMI-NIBIB Interfaces Initiative. Ryan J. Tibshirani was supported by NSF grant DMS-1309174.
## author_header end
## license_header begin
## epiforecast is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, version 2 of the License.
##
## epiforecast is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with epiforecast.  If not, see <http://www.gnu.org/licenses/>.
## license_header end

##' @include namesp.R
NULL

##' Map a function over the natural (Cartesian/other) join of array-like objects
##'
##' @param f the function to map
##' @param arraylike.args a list of array-like objects with named dimnames
##'   (including "scalars" with \code{\link{ndimp}} of 0) and/or
##'   \code{\link{no_join}} objects
##' @return an object of \code{class} \code{"array"} and \code{mode}
##'   \code{"list"} containing outputs from \code{f}, or a single output from
##'   \code{f} if all \code{arraylike.args} are scalars or \code{no_join}'s
##' @details The function \code{f} will be called with a number of arguments
##'   equal to the number of array-like arguments, with the argument names
##'   specified in the \code{arraylike.args} list; each argument will correspond
##'   to an element of one of the \code{arraylike.args}.
##'   \code{\link{dimnamesnamesp}} will be used on each array-like object to
##'   determine what indexing \code{colnames} it would have if melted; the
##'   result will have \code{\link{dimnamesnamesp}} containing all unique
##'   \code{\link{dimnamesnamesp}} from each of the arguments. For any two
##'   dimnames elements of with the same name selected from any of the arraylike
##'   arguments, either (a) the two should be identical, or (b) at least one
##'   should be trivial (NULL or repeated ""'s). Other types of objects can be
##'   wrapped in a list of class \code{"no_join"} using \code{\link{no_join}}
##'   and included in \code{arraylike.args}; they will be treated as scalars
##'   (constants), will not affect the number or naming of dimensions; the
##'   corresponding argument fed to \code{f} is always just the object wrapped
##'   inside the \code{no_join} object. This may be necessary if the same object
##'   should be used for all calls to \code{f} but the object appears to be
##'   array-like, to prevent new dimensions from being created or expected.
##'
##' @rdname map_join
##' @seealso no_join
##' @export
map_join_ = function(f, arraylike.args,
                     eltname.mismatch.behavior=c("error","intersect"),
                     lapply_variant=parallel::mclapply, shuffle=TRUE,
                     progress.output=TRUE,
                     cache.prefix=NULL) {
  f <- match.fun(f)
  eltname.mismatch.behavior <- match.arg(eltname.mismatch.behavior)
  cache.dir =
    if (is.null(cache.prefix)) {
      NULL
    } else {
      dirname(cache.prefix)
    }
  if (!is.null(cache.dir) && !dir.exists(cache.dir)) {
    dir.create(cache.dir, recursive=TRUE)
  }
  ## todo allow for manually specifying index.dnnp?  make sure to drop exactly the index dimensions in each inputs
  index.dnp = list()
  for (arraylike.arg.i in seq_along(arraylike.args)) {
    arraylike.arg = arraylike.args[[arraylike.arg.i]]
    arraylike.arg.name = namesp(arraylike.args)[[arraylike.arg.i]]
    arg.dnp = dimnamesp(arraylike.arg)
    if (length(arg.dnp) == 0L && class(arraylike.arg) != "no_join") {
      ## warning (sprintf("arg %d had ndimp of 0L but was not marked no_join; marking as no_join now", arraylike.arg.i))
      arraylike.args[[arraylike.arg.i]] <- arraylike.arg <- no_join(arraylike.arg)
    }
    for (arg.dimension.i in seq_along(arg.dnp)) {
      dimension.name = names(arg.dnp)[[arg.dimension.i]]
      if (is.null(dimension.name) || dimension.name=="") {
        stop (sprintf('All dimensions must be (nontrivially) named.  Problem with arg %d (namep\'d "%s") dimension %d.',
                      arraylike.arg.i, arraylike.arg.name, arg.dimension.i))
      }
      dimension.eltnames = arg.dnp[[arg.dimension.i]]
      ## xxx may want to pre-allocate list with proper dnnp's
      existing.eltnames = index.dnp[[dimension.name]]
      if (is.null(existing.eltnames)) {
        ## no previous arg with this dimension; make dimension with these eltnames
        index.dnp[[dimension.name]] <- dimension.eltnames
      } else if (length(existing.eltnames) != length(dimension.eltnames)) {
        if (eltname.mismatch.behavior == "error" ||
            eltname.mismatch.behavior == "intersect" &&
            (all(existing.eltnames=="") ||
             all(dimension.eltnames==""))
            ) {
          ## there is a length mismatch that we don't want to or can't fix by
          ## taking the eltnames intersection
          stop (sprintf('Inconsistent lengths found for dimension named "%s".  Length of dimension in arg %d (namep\'d "%s") (dimension %d): %d.  Previous length: %d.',
                        dimension.name, arraylike.arg.i, arraylike.arg.name, arg.dimension.i, length(dimension.eltnames), length(existing.eltnames)))
        } else {
          ## allow other eltnames checks to occur
        }
      } else if (any(existing.eltnames != dimension.eltnames)) {
        if (all(existing.eltnames=="")) {
          ## no pre-existing eltnames; assign
          index.dnp[[dimension.name]] <- dimension.eltnames
        } else if (all(dimension.eltnames=="")) {
          ## no need to do anything; should use existing eltnames
        } else {
          ## eltnames's don't match, and not because one was actually not named.
          if (eltname.mismatch.behavior == "error") {
            stop (sprintf('dimnames associated with dimension named "%s" do not match.  Associated dimnames in arg %d (namep\'d "%s") (dimension %d): %s.  Previous associated dimnames: %s.',
                          dimension.name, arraylike.arg.i, arraylike.arg.name, arg.dimension.i, paste(utils::capture.output(dput(dimension.eltnames)), collapse=" "), paste(utils::capture.output(dput(existing.eltnames)), collapse=" ")))
          } else if (eltname.mismatch.behavior == "intersect") {
            index.dnp[[dimension.name]] <- intersect(existing.eltnames, dimension.eltnames)
          } else {
            stop (sprintf('Unrecognized/unhandled eltname.mismatch.behavior "%s".', eltname.mismatch.behavior))
          }
        }
      } else {
        ## no need to do anything; eltnames's match
      }
    }
  }

  index.dimension.lengths = vapply(index.dnp, length, 1L)
  result.to.arg.dimension.maps = lapply(
    arraylike.args, function(arraylike.arg) {
      match(dimnamesnamesp(arraylike.arg), names(index.dnp))
    }
  )
  perm =
    if (shuffle) {
      sample.int(prod(index.dimension.lengths))
    } else {
      seq_len(prod(index.dimension.lengths))
    }
  length.perm = length(perm)
  result = lapply_variant(seq_along(perm), function(job.i) {
    result.elt.i = perm[[job.i]]
    if (progress.output && job.i == signif(job.i, 1L)) {
      print(paste0(job.i,"/",length.perm))
    }
    indices = stats::setNames(as.vector(arrayInd(result.elt.i, index.dimension.lengths)), names(index.dimension.lengths))
    cache.file =
      if (is.null(cache.prefix)) {
        NULL
      } else {
        names.or.is = lapply(seq_along(indices), function(index.i) {
          index = indices[[index.i]]
          eltname = index.dnp[[index.i]][[index]]
          if (eltname != "") {
            gsub("/","-",eltname)
          } else {
            index
          }
        })
        paste0(cache.prefix,".",paste(names.or.is, collapse="."),".rds")
      }
    subresult =
      if (!is.null(cache.file) && file.exists(cache.file)) {
        readRDS(cache.file)
      } else {
        args =
          arraylike.args %>>%
          {stats::setNames(seq_along(.), names(.))} %>>%
          lapply(function(arraylike.arg.i) {
            arraylike.arg = arraylike.args[[arraylike.arg.i]]
            arraylike.arg.indices =
              indices[result.to.arg.dimension.maps[[arraylike.arg.i]]]
            arg =
              if (ndimp(arraylike.arg) == 0L) {
                stopifnot(class(arraylike.arg)=="no_join")
                arraylike.arg[[1L]]
              } else {
                arraylike.arg[t(as.matrix(arraylike.arg.indices))][[1L]]
              }
            arg
          })
        computed.subresult = do.call(f, args)
        if (!is.null(cache.file)) {
          saveRDS(computed.subresult, cache.file)
        }
        computed.subresult
      }
    subresult
  })
  if (shuffle) {
    result[perm] <- result
  }
  if (length(index.dimension.lengths) > 0L) {
    dim(result) <- index.dimension.lengths
    dimnames(result) <- index.dnp
  } else {
    result <- result[[1L]]
  }
  return (result)
}

##' @details \code{map_join} is provided as a potentially more convenient
##'   interface, eliminating the need to explicitly form a list of arraylike
##'   args; it converts the \code{...} arguments into a list and delegates to
##'   \code{map_join_}
##'
##' @param ... array-like objects with named dimnames, converted into an
##'   \code{arraylike.args} parameter using \code{list(...)}
##'
##' @examples
##' map_join(`*`, 2L,3L, lapply_variant=lapply)
##' map_join(`*`,
##'          with_dimnamesnames(2:3,"A"),
##'          with_dimnamesnames(1:3,"B")) %>>%
##'   {mode(.) <- "numeric"; .}
##' map_join(`*`,
##'          vector_as_named_array(2:3,"A",letters[1:2]),
##'          with_dimnamesnames(array(1:6,2:3), c("A","B"))) %>>%
##'   {mode(.) <- "numeric"; .}
##' cache.dir = tempfile()
##' map_join(`*`,
##'          vector_as_named_array(2:3,"A",letters[1:2]),
##'          with_dimnamesnames(1:3,"B"),
##'          cache.prefix=file.path(cache.dir,"outer_product")) %>>%
##' {mode(.) <- "numeric"; .}
##' arraylike.args = list(NULL
##'   , A=array(1:24,2:4) %>>%
##'     {dimnames(.) <- list(DA=paste0("S",1:2),DB=1:3,DC=1:4); .}
##'   , B=vector_as_named_array_(c(2.0,2.1), "DA", c("S1","S2"))
##'   , C=matrix(1:4, 2L,2L) %>>%
##'       {dimnames(.) <- list(DA=paste0("S",1:2),DA=paste0("S",1:2)); .}
##'   , D=142
##'   ## , E=1:5
##'   , F=vector_as_named_array_(11:14, "DC", 1:4)
##'   ## , G=c(S1=1,S2=2)
##' )[-1L]
##' map_join_(list, arraylike.args)[[DA="S1",DB=1L,DC=1L]]
##'
##' @rdname map_join
##' @export
map_join = function(f, ...,
                    eltname.mismatch.behavior=c("error","intersect"),
                    lapply_variant=parallel::mclapply, shuffle=TRUE,
                    progress.output=TRUE,
                    cache.prefix=NULL) {
  arraylike.args = list(...)
  eltname.mismatch.behavior <- match.arg(eltname.mismatch.behavior)
  map_join_(f, arraylike.args,
            eltname.mismatch.behavior=eltname.mismatch.behavior,
            lapply_variant=lapply_variant, shuffle=shuffle,
            progress.output=progress.output,
            cache.prefix=cache.prefix)
}

##' Mark an array-like or other argument to be used like a constant/scalar in \code{\link{map_join}}
##'
##' @param x the argument to mark
##' @return an object of class \code{"map_join"} wrapping \code{x}
##'
##' @examples
##' map_join(`+`, with_dimnamesnames(1:3,"A"), with_dimnamesnames(1:3,"A"))
##' map_join(`+`, with_dimnamesnames(1:3,"A"), no_join(with_dimnamesnames(1:3,"A")))
##' @export
no_join = function(x) {
  structure(list(x), class="no_join")
}

## todo make map_join work with data.frame inputs as well?
## todo side effect only variant
## todo check intersect behavior --- are the correct things actually selected and lined up?