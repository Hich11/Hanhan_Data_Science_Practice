
## Reference: http://www.analyticsvidhya.com/blog/2016/07/platt-scaling-isotonic-regression-minimize-logloss-error/?utm_content=buffer2f3d5&utm_medium=social&utm_source=facebook.com&utm_campaign=buffer

path<- "[your data folder path]"
setwd(path)

train <- read.csv("blood_train.csv", header = TRUE)
str(train)
test <- read.csv("blood_test.csv", header = TRUE)
str(test)

library("dplyr")
# volumn is closely correlated to the number of donations, remove it
# remove ID too
train <- select(train, -c(X, Total.Volume.Donated..c.c..))
str(train)
test <- select(test, -c(X, Total.Volume.Donated..c.c..))
str(test)


# convert the label into factor for classification purpose
train$Made.Donation.in.March.2007 <- as.factor(train$Made.Donation.in.March.2007)

# split training data for cross validation
set.seed(410)
cv_train_rows <- sample(nrow(train), floor(nrow(train)*0.85))
cv_train <- train[cv_train_rows,]
cv_test <- train[-cv_train_rows,]

## Note: In real world, we need to do more feature engineering before the following operations!

library(randomForest)
model_rf <- randomForest(Made.Donation.in.March.2007~., data = cv_train, keep.forest = T, importance = T)
cv_predict <- as.data.frame(predict(model_rf, type = "prob"))
str(cv_predict)

# predefine LogLoss function
LogLoss<-function(act, pred)
{
  eps = 1e-15;
  nr = length(pred)
  pred = matrix(sapply( pred, function(x) max(eps,x)), nrow = nr) 
  pred = matrix(sapply( pred, function(x) min(1-eps,x)), nrow = nr)
  ll = sum(act*log(pred) + (1-act)*log(1-pred))
  ll = ll * -1/(length(act)) 
  return(ll);
}

# calculate logloss wihtout Platt Scaling
LogLoss(as.numeric(as.character(cv_test$Made.Donation.in.March.2007)), cv_predict$`1`)
## 11.9268

# using Platt Scaling
df <- data.frame(cv_predict$`1`, cv_train$Made.Donation.in.March.2007)
colnames(df) <- c("predict_value", "actual_value")
model_LogisticRegresion <- glm(actual_value~predict_value, data = df, family = binomial)

cv_predict_platt <- predict(model_LogisticRegresion, df[1], type = "response")
LogLoss(as.numeric(as.character(cv_test$Made.Donation.in.March.2007)), cv_predict_platt)
## 3.575357

# reality plot
plot(c(0,1),c(0,1), col="grey",type="l",xlab = "Mean Prediction",ylab="Observed Fraction")
reliability.plot <- function(obs, pred, bins=10, scale=T) {
  # Plots a reliability chart and histogram of a set of predicitons from a classifier
  #
  # Args:
  # obs: Vector of true labels. Should be binary (0 or 1)
  # pred: Vector of predictions of each observation from the classifier. Should be real
  # number
  # bins: The number of bins to use in the reliability plot
  # scale: Scale the pred to be between 0 and 1 before creating reliability plot
  require(plyr)
  library(Hmisc)
  min.pred <- min(pred)
  max.pred <- max(pred)
  min.max.diff <- max.pred - min.pred
  if (scale) {
    pred <- (pred - min.pred) / min.max.diff 
  }
  bin.pred <- cut(pred, bins)
  k <- ldply(levels(bin.pred), function(x) {
    idx <- x == bin.pred
    c(sum(obs[idx]) / length(obs[idx]), mean(pred[idx]))
  })
  not.nan.idx <- !is.nan(k$V2)
  k <- k[not.nan.idx,]
  return(k)
}


## The one closer to the grey line is more accurate
# Without Platt Scaling
k1 <-reliability.plot(as.numeric(as.character(cv_train$Made.Donation.in.March.2007)),cv_predict$`1`,bins = 5)
k1
lines(k1$V2, k1$V1, xlim=c(0,1), ylim=c(0,1), xlab="Mean Prediction", ylab="Observed Fraction", col="red", type="o", main="Reliability Plot")
# With Platt Scaling
k2 <-reliability.plot(as.numeric(as.character(cv_train$Made.Donation.in.March.2007)),cv_predict_platt,bins = 5)
k2
lines(k2$V2, k2$V1, xlim=c(0,1), ylim=c(0,1), xlab="Mean Prediction", ylab="Observed Fraction", col="blue", type="o", main="Reliability Plot")

legend("topright",lty=c(1,1),lwd=c(2.5,2.5),col=c("blue","red"),legend = c("platt scaling","without plat scaling"))



# Do Prediction on Test data

## without platt scaling, probability prediction for both label values (0,1)
predict_test <- as.data.frame(predict(model_rf, newdata = test, type = "prob"))
summary(predict_test)
str(predict_test)

## with platt scaling, probability prediction for label value 1
df_test <- data.frame(predict_test$`1`)
str(df_test)
colnames(df_test) <- c("predict_value")
predict_test_platt <- predict(model_LogisticRegresion, df_test, type = "response")
summary(predict_test_platt)
str(predict_test_platt)


##************************Isotonic Regression***************************##

fit.isoreg <- function(iso, x0) 
{
  o = iso$o
  if (is.null(o)) 
    o = 1:length(x)
  x = iso$x[o]
  y = iso$yf
  ind = cut(x0, breaks = x, labels = FALSE, include.lowest = TRUE)
  min.x <- min(x)
  max.x <- max(x)
  adjusted.knots <- iso$iKnots[c(1, which(iso$yf[iso$iKnots] > 0))]
  fits = sapply(seq(along = x0), function(i) {
    j = ind[i]
    
    # Handles the case where unseen data is outside range of the training data
    if (is.na(j)) {
      if (x0[i] > max.x) j <- length(x)
      else if (x0[i] < min.x) j <- 1
    }
    
    # Find the upper and lower parts of the step
    upper.step.n <- min(which(adjusted.knots > j))
    upper.step <- adjusted.knots[upper.step.n]
    lower.step <- ifelse(upper.step.n==1, 1, adjusted.knots[upper.step.n -1] )
    
    # Perform a liner interpolation between the start and end of the step
    denom <- x[upper.step] - x[lower.step] 
    denom <- ifelse(denom == 0, 1, denom)
    val <- y[lower.step] + (y[upper.step] - y[lower.step]) * (x0[i] - x[lower.step]) / (denom)
    
    # Ensure we bound the probabilities to [0, 1]
    val <- ifelse(val > 1, max.x, val)
    val <- ifelse(val < 0, min.x, val)
    val <- ifelse(is.na(val), max.x, val) # Bit of a hack, NA when at right extreme of distribution
    val
  })
  fits
}


# remove the duplicated predict values
duplicated_idx <- duplicated(cv_predict$`1`)
cv_predict_unique <- cv_predict$`1`[!duplicated_idx]

cv_train$Made.Donation.in.March.2007 <- as.numeric(as.character(cv_train$Made.Donation.in.March.2007))
cv_actual_unique <- cv_train$Made.Donation.in.March.2007[!duplicated_idx]

model_iso <- isoreg(cv_predict_unique, cv_actual_unique)

plot(model_iso,plot.type = "row")

cv_predict_isotonic <- fit.isoreg(model_iso, cv_predict$`1`)
LogLoss(as.numeric(as.character(cv_test$Made.Donation.in.March.2007)), cv_predict_isotonic)
# 11.53349

# reliability plot, the line closer to the grey line, more accurate (less logloss)
plot(c(0,1),c(0,1), col="grey",type="l",xlab = "Mean Prediction",ylab="Observed Fraction")
k1<-reliability.plot(as.numeric(as.character(cv_train$Made.Donation.in.March.2007)),cv_predict$`1`,bins = 5)
lines(k1$V2, k1$V1, xlim=c(0,1), ylim=c(0,1), xlab="Mean Prediction", ylab="Observed Fraction", col="red", type="o", main="Reliability Plot")

k2<-reliability.plot(as.numeric(as.character(cv_train$Made.Donation.in.March.2007)),cv_predict_isotonic,bins = 5)
lines(k2$V2, k2$V1, xlim=c(0,1), ylim=c(0,1), xlab="Mean Prediction", ylab="Observed Fraction", col="blue", type="o", main="Reliability Plot")

legend("topright",lty=c(1,1),lwd=c(2.5,2.5),col=c("blue","red"),legend = c("isotonic scaling","without isotonic scaling"))

# make prediction on test data
predict_test_isotonic<-as.data.frame(fit.isoreg(model_iso,df_test$predict_value))
summary(predict_test_isotonic)
str(predict_test_isotonic)
