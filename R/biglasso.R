biglasso <- function(X, y, row.idx = 1:nrow(X),
                     penalty = c("lasso", "ridge", "enet"),
                     family = c("gaussian","binomial"), 
                     alg.logistic = c("Newton", "MM"),
                     screen = c("SSR", "SEDPP", "SSR-Dome", "SSR-BEDPP","SEDPP-No-Active", "None"),
                     safe.thresh = 0,
                     ncores = 1, alpha = 1,
                     lambda.min = ifelse(nrow(X) > ncol(X),.001,.05), 
                     nlambda = 100, lambda.log.scale = TRUE,
                     lambda, eps = 1e-7, max.iter = 1000, 
                     dfmax = ncol(X)+1,
                     penalty.factor = rep(1, ncol(X)), 
                     warn = TRUE, output.time = FALSE,
                     verbose = FALSE) {
  # Coersion
  family <- match.arg(family)
  penalty <- match.arg(penalty)
  alg.logistic <- match.arg(alg.logistic)
  screen <- match.arg(screen)
  lambda.min <- max(lambda.min, 1.0e-6)
  
  if (identical(penalty, "lasso")) {
    alpha <- 1
  } else if (identical(penalty, 'ridge')) {
    alpha <- 0.0001 ## equivalent to ridge regression
  } else {
    if (alpha >= 1 || alpha <= 0) {
      stop("alpha must be between 0 and 1 for elastic net penalty.")
    } else {
      alpha <- alpha
    }
  }

  if (nlambda < 2) stop("nlambda must be at least 2")
  # subset of the response vector
  y <- y[row.idx]

  if (any(is.na(y))) stop("Missing data (NA's) detected.  Take actions (e.g., removing cases, removing features, imputation) to eliminate missing data before fitting the model.")

  if (class(y) != "numeric") {
    tmp <- try(y <- as.numeric(y), silent=TRUE)
    if (class(tmp)[1] == "try-error") stop("y must numeric or able to be coerced to numeric")
  }

  if (family == 'binomial') {
    if (length(table(y)) > 2) {
      stop("Attemping to use family='binomial' with non-binary data")
    }
    if (!identical(sort(unique(y)), 0:1)) {
      y <- as.numeric(y==max(y))
    }
  }

  if (family=="gaussian") {
    yy <- y - mean(y)
  } else {
    yy <- y
  }

  p <- ncol(X)
  if (length(penalty.factor) != p) stop("penalty.factor does not match up with X")
  if (storage.mode(penalty.factor) != "double") storage.mode(penalty.factor) <- "double"
  n <- length(row.idx) ## subset of X. idx: indices of rows.

  if (missing(lambda)) {
    user.lambda <- FALSE
    lambda <- rep(0.0, nlambda);
  } else {
    nlambda <- length(lambda)
    user.lambda <- TRUE
  }

  ## fit model
  if (output.time) {
    cat("\nStart biglasso: ", format(Sys.time()), '\n')
  }
  if (family == 'gaussian') {
    if (screen == "SEDPP") {
      res <- .Call("cdfit_gaussian_edpp_active", X@address, yy, as.integer(row.idx-1),
                   lambda, as.integer(nlambda), as.integer(lambda.log.scale),
                   lambda.min, alpha,
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor,
                   as.integer(dfmax), as.integer(ncores),
                   PACKAGE = 'biglasso')
    } else if (screen == 'SEDPP-No-Active') {
      res <- .Call("cdfit_gaussian_edpp", X@address, yy, as.integer(row.idx-1),
                   lambda, as.integer(nlambda), as.integer(lambda.log.scale),
                   lambda.min, alpha,
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor,
                   as.integer(dfmax), as.integer(ncores),
                   PACKAGE = 'biglasso')
    } else if (screen == "SSR") {
      res <- .Call("cdfit_gaussian_hsr", X@address, yy, as.integer(row.idx-1),
                   lambda, as.integer(nlambda), as.integer(lambda.log.scale),
                   lambda.min, alpha,
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor,
                   as.integer(dfmax), as.integer(ncores), as.integer(verbose),
                   PACKAGE = 'biglasso')
    } else if (screen == 'SSR-Dome') {
      res <- .Call("cdfit_gaussian_hsr_dome", X@address, yy, as.integer(row.idx-1),
                   lambda, as.integer(nlambda), as.integer(lambda.log.scale),
                   lambda.min, alpha,
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor,
                   as.integer(dfmax), as.integer(ncores), safe.thresh, 
                   as.integer(verbose),
                   PACKAGE = 'biglasso')
    } else if (screen == 'SSR-BEDPP') {
      res <- .Call("cdfit_gaussian_hsr_bedpp", X@address, yy, as.integer(row.idx-1),
                   lambda, as.integer(nlambda), as.integer(lambda.log.scale),
                   lambda.min, alpha,
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor,
                   as.integer(dfmax), as.integer(ncores), safe.thresh, 
                   as.integer(verbose),
                   PACKAGE = 'biglasso')
    } else { # screen == 'None'
      res <- .Call("cdfit_gaussian", X@address, yy, as.integer(row.idx-1),
                   lambda, as.integer(nlambda), as.integer(lambda.log.scale),
                   lambda.min, alpha,
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor,
                   as.integer(dfmax), as.integer(ncores), as.integer(verbose),
                   PACKAGE = 'biglasso')
    }
    
    a <- rep(mean(y), nlambda)
    b <- Matrix(res[[1]], sparse = T)
    center <- res[[2]]
    scale <- res[[3]]
    lambda <- res[[4]]
    loss <- res[[5]]
    iter <- res[[6]]
    rejections <- res[[7]]
    
    if (screen == 'SSR-Dome' || screen == 'SSR-BEDPP') {
      safe_rejections <- res[[8]]
      col.idx <- res[[9]]
    } else {
      col.idx <- res[[8]]
    }
    
  } else if (family == 'binomial') {
    if (alg.logistic == 'MM') {
      res <- .Call("cdfit_binomial_hsr_approx", X@address, yy, as.integer(row.idx-1), 
                   lambda, as.integer(nlambda), lambda.min, alpha, 
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor, 
                   as.integer(dfmax), as.integer(ncores), as.integer(warn),
                   as.integer(verbose),
                   PACKAGE = 'biglasso')
    } else {
      res <- .Call("cdfit_binomial_hsr", X@address, yy, as.integer(row.idx-1), 
                   lambda, as.integer(nlambda), lambda.min, alpha, 
                   as.integer(user.lambda | any(penalty.factor==0)),
                   eps, as.integer(max.iter), penalty.factor, 
                   as.integer(dfmax), as.integer(ncores), as.integer(warn),
                   as.integer(verbose),
                   PACKAGE = 'biglasso')
    }
    a <- res[[1]]
    b <- Matrix(res[[2]], sparse = T)
    center <- res[[3]]
    scale <- res[[4]]
    lambda <- res[[5]]
    loss <- res[[6]]
    iter <- res[[7]]
    rejections <- res[[8]]
    col.idx <- res[[9]]
  } else {
    stop("Current version only supports Gaussian or Binominal response!")
  }
  if (output.time) {
    cat("\nEnd biglasso: ", format(Sys.time()), '\n')
  }
  # p.keep <- length(col.idx)
  col.idx <- col.idx + 1 # indices (in R) for which variables have scale > 1e-6
 
  ## Eliminate saturated lambda values, if any
  ind <- !is.na(iter)
  if (family != "gaussian") a <- a[ind]
  b <- b[, ind, drop=FALSE]
  iter <- iter[ind]
  lambda <- lambda[ind]
  loss <- loss[ind]

  if (warn & any(iter==max.iter)) warning("Algorithm failed to converge for some values of lambda")

  ## Unstandardize coefficients:
  beta <- Matrix(0, nrow = (p+1), ncol = length(lambda), sparse = T)
  bb <- b / scale[col.idx]
  beta[col.idx+1, ] <- bb
  beta[1,] <- a - crossprod(center[col.idx], bb)

  ## Names
  varnames <- if (is.null(colnames(X))) paste("V", 1:p, sep="") else colnames(X)
  varnames <- c("(Intercept)", varnames)
  dimnames(beta) <- list(varnames, round(lambda, digits = 4))

  ## Output
  return.val <- list(
    beta = beta,
    iter = iter,
    lambda = lambda,
    penalty = penalty,
    family = family,
    alpha = alpha,
    loss = loss,
    penalty.factor = penalty.factor,
    n = n,
    center = center,
    scale = scale,
    y = yy,
    screen = screen,
    col.idx = col.idx,
    rejections = rejections
  )
  if (screen == 'SSR-Dome' || screen == 'SSR-BEDPP') {
    return.val$safe_rejections <- safe_rejections
  }
  
  val <- structure(return.val, class = c("biglasso", 'ncvreg'))
  val
}
