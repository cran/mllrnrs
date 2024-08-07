## ----setup--------------------------------------------------------------------
# nolint start
library(mlexperiments)
library(mllrnrs)


## -----------------------------------------------------------------------------
library(mlbench)
data("DNA")
dataset <- DNA |>
  data.table::as.data.table() |>
  na.omit()

feature_cols <- colnames(dataset)[160:180]
target_col <- "Class"


## -----------------------------------------------------------------------------
seed <- 123
if (isTRUE(as.logical(Sys.getenv("_R_CHECK_LIMIT_CORES_")))) {
  # on cran
  ncores <- 2L
} else {
  ncores <- ifelse(
    test = parallel::detectCores() > 4,
    yes = 4L,
    no = ifelse(
      test = parallel::detectCores() < 2L,
      yes = 1L,
      no = parallel::detectCores()
    )
  )
}
options("mlexperiments.bayesian.max_init" = 10L)
options("mlexperiments.optim.xgb.nrounds" = 100L)
options("mlexperiments.optim.xgb.early_stopping_rounds" = 10L)


## -----------------------------------------------------------------------------
data_split <- splitTools::partition(
  y = dataset[, get(target_col)],
  p = c(train = 0.7, test = 0.3),
  type = "stratified",
  seed = seed
)

train_x <- model.matrix(
  ~ -1 + .,
  dataset[data_split$train, .SD, .SDcols = feature_cols]
)
train_y <- as.integer(dataset[data_split$train, get(target_col)]) - 1L


test_x <- model.matrix(
  ~ -1 + .,
  dataset[data_split$test, .SD, .SDcols = feature_cols]
)
test_y <- as.integer(dataset[data_split$test, get(target_col)]) - 1L


## -----------------------------------------------------------------------------
fold_list <- splitTools::create_folds(
  y = train_y,
  k = 3,
  type = "stratified",
  seed = seed
)


## -----------------------------------------------------------------------------
# required learner arguments, not optimized
learner_args <- list(
  objective = "multi:softprob",
  eval_metric = "mlogloss",
  num_class = 3
)

# set arguments for predict function and performance metric,
# required for mlexperiments::MLCrossValidation and
# mlexperiments::MLNestedCV
predict_args <- list(reshape = TRUE)
performance_metric <- metric("bacc")
performance_metric_args <- NULL
return_models <- FALSE

# required for grid search and initialization of bayesian optimization
parameter_grid <- expand.grid(
  subsample = seq(0.6, 1, .2),
  colsample_bytree = seq(0.6, 1, .2),
  min_child_weight = seq(1, 5, 4),
  learning_rate = seq(0.1, 0.2, 0.1),
  max_depth = seq(1, 5, 4)
)
# reduce to a maximum of 10 rows
if (nrow(parameter_grid) > 10) {
  set.seed(123)
  sample_rows <- sample(seq_len(nrow(parameter_grid)), 10, FALSE)
  parameter_grid <- kdry::mlh_subset(parameter_grid, sample_rows)
}

# required for bayesian optimization
parameter_bounds <- list(
  subsample = c(0.2, 1),
  colsample_bytree = c(0.2, 1),
  min_child_weight = c(1L, 10L),
  learning_rate = c(0.1, 0.2),
  max_depth =  c(1L, 10L)
)
optim_args <- list(
  iters.n = ncores,
  kappa = 3.5,
  acq = "ucb"
)


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "grid",
  ncores = ncores,
  seed = seed
)

tuner$parameter_grid <- parameter_grid
tuner$learner_args <- learner_args
tuner$split_type <- "stratified"

tuner$set_data(
  x = train_x,
  y = train_y
)

tuner_results_grid <- tuner$execute(k = 3)
#> 
#> Parameter settings [============================>-------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  

head(tuner_results_grid)
#>    setting_id metric_optim_mean nrounds subsample colsample_bytree min_child_weight learning_rate max_depth      objective
#> 1:          1         1.0107788      27       0.6              0.8                5           0.2         1 multi:softprob
#> 2:          2         0.9822161      35       1.0              0.8                5           0.1         5 multi:softprob
#> 3:          3         1.0097847     100       0.8              0.8                5           0.1         1 multi:softprob
#> 4:          4         0.9850296      20       0.6              0.8                5           0.2         5 multi:softprob
#> 5:          5         0.9807356      34       1.0              0.8                1           0.1         5 multi:softprob
#> 6:          6         0.9734746      46       0.8              0.8                5           0.1         5 multi:softprob
#>    eval_metric num_class
#> 1:    mlogloss         3
#> 2:    mlogloss         3
#> 3:    mlogloss         3
#> 4:    mlogloss         3
#> 5:    mlogloss         3
#> 6:    mlogloss         3


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "bayesian",
  ncores = ncores,
  seed = seed
)

tuner$parameter_grid <- parameter_grid
tuner$parameter_bounds <- parameter_bounds

tuner$learner_args <- learner_args
tuner$optim_args <- optim_args

tuner$split_type <- "stratified"

tuner$set_data(
  x = train_x,
  y = train_y
)

tuner_results_bayesian <- tuner$execute(k = 3)
#> 
#> Registering parallel backend using 4 cores.

head(tuner_results_bayesian)
#>    Epoch setting_id subsample colsample_bytree min_child_weight learning_rate max_depth gpUtility acqOptimum inBounds Elapsed
#> 1:     0          1       0.6              0.8                5           0.2         1        NA      FALSE     TRUE   1.934
#> 2:     0          2       1.0              0.8                5           0.1         5        NA      FALSE     TRUE   2.181
#> 3:     0          3       0.8              0.8                5           0.1         1        NA      FALSE     TRUE   2.060
#> 4:     0          4       0.6              0.8                5           0.2         5        NA      FALSE     TRUE   2.057
#> 5:     0          5       1.0              0.8                1           0.1         5        NA      FALSE     TRUE   1.422
#> 6:     0          6       0.8              0.8                5           0.1         5        NA      FALSE     TRUE   1.505
#>         Score metric_optim_mean nrounds errorMessage      objective eval_metric num_class
#> 1: -1.0093139         1.0093139      51           NA multi:softprob    mlogloss         3
#> 2: -0.9842567         0.9842567      34           NA multi:softprob    mlogloss         3
#> 3: -1.0097517         1.0097517      79           NA multi:softprob    mlogloss         3
#> 4: -0.9766614         0.9766614      17           NA multi:softprob    mlogloss         3
#> 5: -0.9851912         0.9851912      28           NA multi:softprob    mlogloss         3
#> 6: -0.9755198         0.9755198      42           NA multi:softprob    mlogloss         3


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLCrossValidation$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  fold_list = fold_list,
  ncores = ncores,
  seed = seed
)

validator$learner_args <- tuner$results$best.setting[-1]

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- return_models

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> CV fold: Fold2
#> 
#> CV fold: Fold3
#> CV progress [========================================================================================================] 3/3 (100%)
#>                                                                                                                                   

head(validator_results)
#>     fold performance subsample colsample_bytree min_child_weight learning_rate max_depth nrounds      objective eval_metric
#> 1: Fold1   0.4685501 0.5356077        0.8312972                1     0.1099728        10      23 multi:softprob    mlogloss
#> 2: Fold2   0.4179775 0.5356077        0.8312972                1     0.1099728        10      23 multi:softprob    mlogloss
#> 3: Fold3   0.4718162 0.5356077        0.8312972                1     0.1099728        10      23 multi:softprob    mlogloss
#>    num_class
#> 1:         3
#> 2:         3
#> 3:         3


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "grid",
  fold_list = fold_list,
  k_tuning = 3L,
  ncores = ncores,
  seed = seed
)

validator$parameter_grid <- parameter_grid
validator$learner_args <- learner_args
validator$split_type <- "stratified"

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- return_models

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> Parameter settings [============================>-------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  
#> CV fold: Fold2
#> CV progress [====================================================================>-----------------------------------] 2/3 ( 67%)
#> 
#> Parameter settings [============================>-------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  
#> CV fold: Fold3
#> CV progress [========================================================================================================] 3/3 (100%)
#>                                                                                                                                   
#> Parameter settings [============================>-------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  

head(validator_results)
#>     fold performance nrounds subsample colsample_bytree min_child_weight learning_rate max_depth      objective eval_metric
#> 1: Fold1   0.4304667      30       0.8              0.8                5           0.1         5 multi:softprob    mlogloss
#> 2: Fold2   0.3907826      33       0.8              0.8                5           0.1         5 multi:softprob    mlogloss
#> 3: Fold3   0.4183769      25       0.6              1.0                1           0.1         5 multi:softprob    mlogloss
#>    num_class
#> 1:         3
#> 2:         3
#> 3:         3


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "bayesian",
  fold_list = fold_list,
  k_tuning = 3L,
  ncores = ncores,
  seed = seed
)

validator$parameter_grid <- parameter_grid
validator$learner_args <- learner_args
validator$split_type <- "stratified"


validator$parameter_bounds <- parameter_bounds
validator$optim_args <- optim_args

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- TRUE

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> Registering parallel backend using 4 cores.
#> 
#> CV fold: Fold2
#> CV progress [====================================================================>-----------------------------------] 2/3 ( 67%)
#> 
#> Registering parallel backend using 4 cores.
#> 
#> CV fold: Fold3
#> CV progress [========================================================================================================] 3/3 (100%)
#>                                                                                                                                   
#> Registering parallel backend using 4 cores.

head(validator_results)
#>     fold performance subsample colsample_bytree min_child_weight learning_rate max_depth nrounds      objective eval_metric
#> 1: Fold1   0.4607781 0.7285277        0.8178568                1     0.1099728        10      18 multi:softprob    mlogloss
#> 2: Fold2   0.4306211 0.5578915        0.7352097                1     0.1099728        10      24 multi:softprob    mlogloss
#> 3: Fold3   0.4464739 0.5001911        0.8708509                1     0.1099728        10      19 multi:softprob    mlogloss
#>    num_class
#> 1:         3
#> 2:         3
#> 3:         3


## -----------------------------------------------------------------------------
preds_xgboost <- mlexperiments::predictions(
  object = validator,
  newdata = test_x
)


## -----------------------------------------------------------------------------
perf_xgboost <- mlexperiments::performance(
  object = validator,
  prediction_results = preds_xgboost,
  y_ground_truth = test_y
)
perf_xgboost
#>    model performance
#> 1: Fold1   0.4628262
#> 2: Fold2   0.4503222
#> 3: Fold3   0.4535445


## -----------------------------------------------------------------------------
# define the target weights
y_weights <- ifelse(train_y == 1, 0.8, ifelse(train_y == 2, 1.2, 1))
head(y_weights)
#> [1] 1.2 1.2 0.0 0.8 0.8 0.0


## -----------------------------------------------------------------------------
tuner_w_weights <- mlexperiments::MLTuneParameters$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  strategy = "grid",
  ncores = ncores,
  seed = seed
)

tuner_w_weights$parameter_grid <- parameter_grid
tuner_w_weights$learner_args <- c(
  learner_args,
  list(case_weights = y_weights)
)
tuner_w_weights$split_type <- "stratified"

tuner_w_weights$set_data(
  x = train_x,
  y = train_y
)

tuner_results_grid <- tuner_w_weights$execute(k = 3)
#> 
#> Parameter settings [============================>-------------------------------------------------------------------] 3/10 ( 30%)
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  

head(tuner_results_grid)
#>    setting_id metric_optim_mean nrounds subsample colsample_bytree min_child_weight learning_rate max_depth      objective
#>         <int>             <num>   <int>     <num>            <num>            <num>         <num>     <num>         <char>
#> 1:          1         0.9447465      27       0.6              0.8                5           0.2         1 multi:softprob
#> 2:          2         0.9222842      33       1.0              0.8                5           0.1         5 multi:softprob
#> 3:          3         0.9442046     100       0.8              0.8                5           0.1         1 multi:softprob
#> 4:          4         0.9236826      20       0.6              0.8                5           0.2         5 multi:softprob
#> 5:          5         0.9197338      35       1.0              0.8                1           0.1         5 multi:softprob
#> 6:          6         0.9147754      46       0.8              0.8                5           0.1         5 multi:softprob
#>    eval_metric num_class
#>         <char>     <num>
#> 1:    mlogloss         3
#> 2:    mlogloss         3
#> 3:    mlogloss         3
#> 4:    mlogloss         3
#> 5:    mlogloss         3
#> 6:    mlogloss         3


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLCrossValidation$new(
  learner = mllrnrs::LearnerXgboost$new(
    metric_optimization_higher_better = FALSE
  ),
  fold_list = fold_list,
  ncores = ncores,
  seed = seed
)

# append the optimized setting from above with the newly created weights
validator$learner_args <- c(
  tuner$results$best.setting[-1],
  list("case_weights" = y_weights)
)

validator$predict_args <- predict_args
validator$performance_metric <- performance_metric
validator$performance_metric_args <- performance_metric_args
validator$return_models <- return_models

validator$set_data(
  x = train_x,
  y = train_y
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> CV fold: Fold2
#> 
#> CV fold: Fold3
#> CV progress [========================================================================================================] 3/3 (100%)
#>                                                                                                                                   

head(validator_results)
#>      fold performance subsample colsample_bytree min_child_weight learning_rate max_depth nrounds      objective eval_metric
#>    <char>       <num>     <num>            <num>            <num>         <num>     <num>   <int>         <char>      <char>
#> 1:  Fold1   0.4508447 0.5356077        0.8312972                1     0.1099728        10      23 multi:softprob    mlogloss
#> 2:  Fold2   0.4185381 0.5356077        0.8312972                1     0.1099728        10      23 multi:softprob    mlogloss
#> 3:  Fold3   0.4436661 0.5356077        0.8312972                1     0.1099728        10      23 multi:softprob    mlogloss
#>    num_class
#>        <num>
#> 1:         3
#> 2:         3
#> 3:         3


## ----include=FALSE------------------------------------------------------------
# nolint end

