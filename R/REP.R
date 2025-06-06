#' @title Regularized elimination procedure in PLS
#'
#' @description A regularized variable elimination procedure for parsimonious
#' variable selection, where also a stepwise elimination is carried out
#'
#' @param y vector of response values (\code{numeric} or \code{factor}).
#' @param X numeric predictor \code{matrix}.
#' @param ncomp integer number of components (default = 5).
#' @param ratio the proportion of the samples to use for calibration (default = 0.75).
#' @param VIP.threshold thresholding to remove non-important variables (default = 0.5).
#' @param N number of samples in the selection matrix (default = 3).
#'
#' @details A stability based variable selection procedure is adopted, where the
#' samples have been split randomly into a predefined number of training and test sets.
#' For each split, g, the following stepwise procedure is adopted to select the variables.
#' This implementation does not follow the original publication exactly, but
#' it opens for both regression and classification.
#'  
#' @return Returns a vector of variable numbers corresponding to the model 
#' having lowest prediction error.
#'
#' @author Tahir Mehmood, Kristian Hovde Liland, Solve Sæbø.
#'
#' @references T. Mehmood, H. Martens, S. Sæbø, J. Warringer, L. Snipen, A partial 
#' least squares based algorithm for parsimonious variable selection, Algorithms for
#' Molecular Biology 6 (2011).
#'
#' @seealso \code{\link{VIP}} (SR/sMC/LW/RC), \code{\link{filterPLSR}}, \code{\link{shaving}}, 
#' \code{\link{stpls}}, \code{\link{truncation}},
#' \code{\link{bve_pls}}, \code{\link{ga_pls}}, \code{\link{ipw_pls}}, \code{\link{mcuve_pls}},
#' \code{\link{rep_pls}}, \code{\link{spa_pls}},
#' \code{\link{lda_from_pls}}, \code{\link{lda_from_pls_cv}}, \code{\link{setDA}}.
#' 
#' @examples
#' data(gasoline, package = "pls")
#' \dontrun{
#' with( gasoline, rep_pls(octane, NIR) )
#' }
#'
#' @export
rep_pls <- function( y, X, ncomp=5, ratio=0.75, VIP.threshold= 0.5, N=3  ){

  modeltype <- "prediction"
  if (is.factor(y)) {
    modeltype <- "classification"
    y.orig <- as.numeric(y)
    y      <- model.matrix(~ y-1)
    tb     <- names(table(y.orig))
    # tb<-as.numeric(names(table(y)))
  } else {
    y <- as.matrix(y)
  }
  
  # Strip X
  X <- unclass(as.matrix(X))

  # Local variables
  n1 <- dim( X )[1]
  p1 <- dim( X )[2]
  # The elimination
  Z <- X
  Selection.mat<- matrix(0, N,p1)
  for(j in 1:N){
    terminated <- FALSE
    Pg <- NULL
    K  <- floor(n1*ratio) 
    Variable.list <- list()
    predy.list    <- list()
    is.selected <- rep( T, p1 )
    variables   <- which( is.selected ) 
    if (modeltype == "prediction"){
      K    <- floor(n1*ratio)
      temp <- sample(n1)
      calk <- temp[1:K]      
      Zcal <- Z[calk, ];  ycal  <- y[calk,]  
      Ztest<- Z[-calk, ]; ytest <- y[-calk,] 
    } else 
      if(modeltype == "classification"){
        calK <- c() 
        for(jj in 1:length(tb)){
          temp <- sample(which(y.orig==tb[jj]))
          K    <- floor(length(temp)*ratio)
          calK <- c(calK, temp[1:K])
        }      
        Zcal  <- Z[calK, ];  ycal  <- y[calK,]  
        Ztest <- Z[-calK, ]; ytest <- y[-calK,] 
      }
    iter <- 0
    while( !terminated ){  
      # Fitting, and finding optimal number of components
      co <- min(ncomp, ncol(Zcal)-1)
      pls.object <- plsr(y ~ X,  ncomp=co, data = data.frame(y=I(ycal), X=I(Zcal)), validation = "LOO")
      if (modeltype == "prediction"){
        opt.comp <- which.min(pls.object$validation$PRESS[1,])
      } else if (modeltype == "classification"){
        classes <- lda_from_pls_cv(pls.object, Zcal, y.orig[calK], co)
        opt.comp <- which.max(colSums(classes==y.orig[calK]))
      }

      if(modeltype == "prediction"){
        mydata  <- data.frame( yy=c(ycal, ytest) ,ZZ=I(rbind(Zcal, Ztest)) , train= c(rep(TRUE, length(ycal)), rep(FALSE, length(ytest))))
      } else {
        mydata  <- data.frame( yy=I(rbind(ycal, ytest)) ,ZZ=I(rbind(Zcal, Ztest)) , train= c(rep(TRUE, length(y.orig[calK])), rep(FALSE, length(y.orig[-calK]))))
      }
      pls.fit <- plsr(yy ~ ZZ, ncomp=opt.comp, data=mydata[mydata$train,])
      # Make predictions using the established PLS model 
      if (modeltype == "prediction"){
        pred.pls <- predict(pls.fit, ncomp = opt.comp, newdata=mydata[!mydata$train,])
        Pgi <- sqrt(sum((ytest-pred.pls[,,])^2))
        predy.list <- c(predy.list, list(pred.pls[,,]))
      } else if(modeltype == "classification"){
        classes <- lda_from_pls(pls.fit,y.orig[calK],Ztest,opt.comp)[,opt.comp]
        Pgi       <- 100-sum(y.orig[-calK] == classes)/nrow(Ztest)*100
        predy.list<- c(predy.list, list(classes))
      }
      
      Pg  <- c( Pg, Pgi )
      Vip <- VIP(pls.fit,opt.comp=opt.comp)
      VIP.index <- which (as.matrix(Vip) < VIP.threshold)
      if(length(VIP.index) <= (ncomp +1)) {
        VIP.index <- sort(Vip,decreasing=FALSE, index.return = T)$ix [1:ncomp]
      }
      
      is.selected[variables[VIP.index]] <- FALSE
      variables     <- which( is.selected ) 
      Variable.list <- c(Variable.list, list(variables)) 
      Zcal  <- Zcal[,VIP.index]
      Ztest <- Ztest[,VIP.index]
      indd  <- unique( which(apply(Zcal, 2, var)==0),which(apply(Ztest, 2, var)==0))
      Zcal  <- Zcal[, -indd] 
      Ztest <- Ztest[, -indd] 
      if( ncol(Zcal) <= ncomp+1 ){  # terminates if less than (ncomp+1) variables remain
        terminated <- TRUE
      } 
      iter<- iter +1
    }
    opt.iter <- which.min(Pg)
    sel.iter <- opt.iter
    if(opt.iter!=iter){
      for(ii in (opt.iter+1):iter ){
        if (modeltype == "prediction"){
          tst <- t.test( predy.list[[opt.iter]], predy.list[[ii]], paired=T, alternative="greater" )
        } else if(modeltype == "classification"){
          tst <- chisq.test( predy.list[[opt.iter]], predy.list[[ii]])
        }
        if(tst$p.value > 0.1)  {
          sel.iter <- ii
        }
      }
    }
    Selection.mat[j,Variable.list[[sel.iter]]] <- 1 
  }
  selection.prob <- colSums(Selection.mat )/N
  rep.selection  <- which(selection.prob > (mean(selection.prob)+sd(selection.prob)/length(selection.prob)))
  return(list(rep.selection=rep.selection))
}
