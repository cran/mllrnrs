## ----setup--------------------------------------------------------------------
# nolint start
library(mlexperiments)
library(mllrnrs)


## -----------------------------------------------------------------------------
library(mlbench)
data("BostonHousing")
dataset <- BostonHousing |>
  data.table::as.data.table() |>
  na.omit()

feature_cols <- colnames(dataset)[1:13]
target_col <- "medv"
cat_vars <- "chas"


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


## -----------------------------------------------------------------------------
data_split <- splitTools::partition(
  y = dataset[, get(target_col)],
  p = c(train = 0.7, test = 0.3),
  type = "stratified",
  seed = seed
)

train_x <- data.matrix(
  dataset[data_split$train, .SD, .SDcols = feature_cols]
)
train_y <- log(dataset[data_split$train, get(target_col)])


test_x <- data.matrix(
  dataset[data_split$test, .SD, .SDcols = feature_cols]
)
test_y <- log(dataset[data_split$test, get(target_col)])


## -----------------------------------------------------------------------------
fold_list <- splitTools::create_folds(
  y = train_y,
  k = 3,
  type = "stratified",
  seed = seed
)


## -----------------------------------------------------------------------------
# required learner arguments, not optimized
learner_args <- NULL

# set arguments for predict function and performance metric,
# required for mlexperiments::MLCrossValidation and
# mlexperiments::MLNestedCV
predict_args <- NULL
performance_metric <- metric("rmsle")
performance_metric_args <- NULL
return_models <- FALSE

# required for grid search and initialization of bayesian optimization
parameter_grid <- expand.grid(
  num.trees = seq(500, 1000, 500),
  mtry = seq(2, 6, 2),
  min.node.size = seq(1, 9, 4),
  max.depth = seq(1, 9, 4),
  sample.fraction = seq(0.5, 0.8, 0.3)
)
# reduce to a maximum of 10 rows
if (nrow(parameter_grid) > 10) {
  set.seed(123)
  sample_rows <- sample(seq_len(nrow(parameter_grid)), 10, FALSE)
  parameter_grid <- kdry::mlh_subset(parameter_grid, sample_rows)
}

# required for bayesian optimization
parameter_bounds <- list(
  num.trees = c(100L, 1000L),
  mtry = c(2L, 9L),
  min.node.size = c(1L, 20L),
  max.depth = c(1L, 40L),
  sample.fraction = c(0.3, 1.)
)
optim_args <- list(
  iters.n = ncores,
  kappa = 3.5,
  acq = "ucb"
)


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = mllrnrs::LearnerRanger$new(),
  strategy = "grid",
  ncores = ncores,
  seed = seed
)

tuner$parameter_grid <- parameter_grid
tuner$learner_args <- learner_args
tuner$split_type <- "stratified"

tuner$set_data(
  x = train_x,
  y = train_y,
  cat_vars = cat_vars
)

tuner_results_grid <- tuner$execute(k = 3)
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  
#>  Regression: using 'mean squared error' as optimization metric.

head(tuner_results_grid)
#>    setting_id metric_optim_mean num.trees mtry min.node.size max.depth sample.fraction
#> 1:          1        0.04406585       500    2             9         5             0.5
#> 2:          2        0.03987001       500    2             5         5             0.8
#> 3:          3        0.03405954       500    4             9         9             0.5
#> 4:          4        0.09531892      1000    2             9         1             0.5
#> 5:          5        0.09497929       500    2             9         1             0.8
#> 6:          6        0.03046036      1000    6             1         9             0.5


## -----------------------------------------------------------------------------
tuner <- mlexperiments::MLTuneParameters$new(
  learner = mllrnrs::LearnerRanger$new(),
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
  y = train_y,
  cat_vars = cat_vars
)

tuner_results_bayesian <- tuner$execute(k = 3)
#> 
#> Registering parallel backend using 4 cores.

head(tuner_results_bayesian)
#>    Epoch setting_id num.trees mtry min.node.size max.depth sample.fraction gpUtility acqOptimum inBounds Elapsed       Score
#> 1:     0          1       500    2             9         5             0.5        NA      FALSE     TRUE   1.013 -0.04356188
#> 2:     0          2       500    2             5         5             0.8        NA      FALSE     TRUE   1.035 -0.03848441
#> 3:     0          3       500    4             9         9             0.5        NA      FALSE     TRUE   1.064 -0.03375279
#> 4:     0          4      1000    2             9         1             0.5        NA      FALSE     TRUE   0.994 -0.09582667
#> 5:     0          5       500    2             9         1             0.8        NA      FALSE     TRUE   0.070 -0.09470805
#> 6:     0          6      1000    6             1         9             0.5        NA      FALSE     TRUE   0.690 -0.03014795
#>    metric_optim_mean errorMessage
#> 1:        0.04356188           NA
#> 2:        0.03848441           NA
#> 3:        0.03375279           NA
#> 4:        0.09582667           NA
#> 5:        0.09470805           NA
#> 6:        0.03014795           NA


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLCrossValidation$new(
  learner = mllrnrs::LearnerRanger$new(),
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
  y = train_y,
  cat_vars = cat_vars
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#> CV fold: Fold2
#> 
#> CV fold: Fold3

head(validator_results)
#>     fold performance num.trees mtry min.node.size max.depth sample.fraction
#> 1: Fold1  0.04028795       100    9             1         9               1
#> 2: Fold2  0.05592193       100    9             1         9               1
#> 3: Fold3  0.04012856       100    9             1         9               1


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = mllrnrs::LearnerRanger$new(),
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
  y = train_y,
  cat_vars = cat_vars
)

validator_results <- validator$execute()
#> 
#> CV fold: Fold1
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> CV fold: Fold2
#> CV progress [====================================================================>-----------------------------------] 2/3 ( 67%)
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> CV fold: Fold3
#> CV progress [========================================================================================================] 3/3 (100%)
#>                                                                                                                                   
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=====================================>----------------------------------------------------------] 4/10 ( 40%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================>------------------------------------------------] 5/10 ( 50%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=========================================================>--------------------------------------] 6/10 ( 60%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [==================================================================>-----------------------------] 7/10 ( 70%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [============================================================================>-------------------] 8/10 ( 80%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [=====================================================================================>----------] 9/10 ( 90%)
#>  Regression: using 'mean squared error' as optimization metric.
#> 
#> Parameter settings [===============================================================================================] 10/10 (100%)                                                                                                                                  
#>  Regression: using 'mean squared error' as optimization metric.

head(validator_results)
#>     fold performance num.trees mtry min.node.size max.depth sample.fraction
#> 1: Fold1   0.0444887      1000    6             1         9             0.5
#> 2: Fold2   0.0481817       500    4             9         9             0.8
#> 3: Fold3   0.0442502      1000    6             1         9             0.5


## -----------------------------------------------------------------------------
validator <- mlexperiments::MLNestedCV$new(
  learner = mllrnrs::LearnerRanger$new(),
  strategy = "bayesian",
  fold_list = fold_list,
  k_tuning = 3L,
  ncores = ncores,
  seed = 312
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
  y = train_y,
  cat_vars = cat_vars
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
#>     fold performance num.trees mtry min.node.size max.depth sample.fraction
#> 1: Fold1  0.04142935       640    7             1         9       0.7460504
#> 2: Fold2  0.05358418       100    9             1         9       1.0000000
#> 3: Fold3  0.04264248       367    4             5         9       0.8388297


## -----------------------------------------------------------------------------
preds_ranger <- mlexperiments::predictions(
  object = validator,
  newdata = test_x
)


## -----------------------------------------------------------------------------
perf_ranger <- mlexperiments::performance(
  object = validator,
  prediction_results = preds_ranger,
  y_ground_truth = test_y,
  type = "regression"
)
perf_ranger
#>    model performance        mse        msle       mae       mape      rmse      rmsle       rsq      sse
#> 1: Fold1  0.04145400 0.02627203 0.001718434 0.1125978 0.03799847 0.1620865 0.04145400 0.8291229 4.072165
#> 2: Fold2  0.04849306 0.03319570 0.002351577 0.1270962 0.04379366 0.1821969 0.04849306 0.7840903 5.145334
#> 3: Fold3  0.03827309 0.02222906 0.001464829 0.1067541 0.03631993 0.1490941 0.03827309 0.8554189 3.445504


## ----include=FALSE------------------------------------------------------------
# nolint end

