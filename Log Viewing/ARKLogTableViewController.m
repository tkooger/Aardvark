//
//  ARKLogTableViewController.m
//  Aardvark
//
//  Created by Dan Federman on 10/5/14.
//  Copyright (c) 2014 Square, Inc. All rights reserved.
//

#import "ARKLogTableViewController.h"

#import "ARKAardvarkLog.h"
#import "ARKIndividualLogViewController.h"
#import "ARKDefaultLogFormatter.h"
#import "ARKLogController.h"
#import "ARKScreenshotViewController.h"
#import "UIActivityViewController+ARKAdditions.h"


@interface ARKLogTableViewController () <UIActionSheetDelegate>

@property (nonatomic, copy, readwrite) NSArray *logs;
@property (nonatomic, assign, readwrite) BOOL viewWillAppearForFirstTimeCalled;

@end


@implementation ARKLogTableViewController

#pragma mark - Initialization

- (instancetype)init;
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _logFormatter = [ARKDefaultLogFormatter new];
    
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIViewController

- (void)viewDidLayoutSubviews;
{
    [super viewDidLayoutSubviews];
    
    [self _scrollTableViewToBottomAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [self _reloadLogs];
    
    if (!self.viewWillAppearForFirstTimeCalled) {
        [self _viewWillAppearForFirstTime:animated];
        self.viewWillAppearForFirstTimeCalled = YES;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
    
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
    
    [super viewWillDisappear:animated];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 34.0;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    
    self.title = @"Logs";
}

- (void)_viewWillAppearForFirstTime:(BOOL)animated;
{
    UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(_openActivitySheet:)];
    UIBarButtonItem *deleteButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(_clearLogs:)];
    
    self.navigationItem.rightBarButtonItems = @[shareButton, deleteButton];
    
    [self _scrollTableViewToBottomAnimated:NO];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex;
{
    if (buttonIndex == actionSheet.destructiveButtonIndex) {
        [[ARKLogController sharedInstance] clearLogs];
        [self _reloadLogs];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex;
{
    NSAssert(sectionIndex == 0, 0, @"There is only one section index!");
    return self.logs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    static NSString *const sSQDebugLog = @"SQDebugLog";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sSQDebugLog];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sSQDebugLog];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    NSInteger index = [indexPath row];
    ARKAardvarkLog *currentLog = self.logs[index];
    
    ARKAardvarkLog *firstPaymentLog = nil;
    for (NSInteger i = index; i >= 0; i--) {
        firstPaymentLog = self.logs[i];
        if (firstPaymentLog.type == ARKLogTypeSeparator) {
            break;
        } else {
            firstPaymentLog = nil;
        }
    }
    
    NSTimeInterval delta = firstPaymentLog ? [currentLog.createdAt timeIntervalSinceDate:firstPaymentLog.createdAt] : 0.0;
    if (delta > 60.0) {
        cell.textLabel.text = [NSString stringWithFormat:@"+%.fm\t%@", delta / 60.0, currentLog.text];
    } else if (delta > 1.0) {
        cell.textLabel.text = [NSString stringWithFormat:@"+%.1f\t%@", delta, currentLog.text];
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"+0\t%@", currentLog.text];;
    }
    
    UIColor *textColor = nil;
    UIColor *backgroundColor = nil;
    switch (currentLog.type) {
        case ARKLogTypeSeparator:
        {
            static NSCalendar *calendar = nil;
            static dispatch_once_t onceToken = 0;
            dispatch_once(&onceToken, ^{
                calendar = [NSCalendar currentCalendar];
            });
            
            NSCalendarUnit dayComponents = (NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay);
            NSDateComponents *logDateComponents = [calendar components:dayComponents fromDate:currentLog.createdAt];
            NSDateComponents *todayDateComponents = [calendar components:dayComponents fromDate:[NSDate date]];

            if ([logDateComponents isEqual:todayDateComponents]) {
                // Log was created today.
                cell.textLabel.text = [NSString stringWithFormat:@"%@ -- %@",
                                       currentLog.text,
                                       [NSDateFormatter localizedStringFromDate:currentLog.createdAt dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle]];
            } else {
                cell.textLabel.text = [NSString stringWithFormat:@"%@ -- %@",
                                       currentLog.text,
                                       [NSDateFormatter localizedStringFromDate:currentLog.createdAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
            }
            
            textColor = [UIColor whiteColor];
            backgroundColor = [UIColor blueColor];
            break;
        }
        case ARKLogTypeError:
            textColor = [UIColor whiteColor];
            backgroundColor = [UIColor redColor];
            break;
        case ARKLogTypeDefault:
            textColor = [UIColor blackColor];
            backgroundColor = [UIColor clearColor];
            break;
        default:
            break;
    }
    
    if ([cell respondsToSelector:@selector(separatorInset) /* iOS 7 or later */]) {
        cell.textLabel.textColor = textColor;
        cell.backgroundColor = backgroundColor;
    } else {
        // cell.backgroundColor doesn't work on iOS 6. Instead, set the text color.
        cell.textLabel.textColor = [textColor isEqual:[UIColor blackColor]] ? textColor : backgroundColor;
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    ARKAardvarkLog *log = self.logs[[indexPath row]];
    if (log.image != nil) {
        ARKScreenshotViewController *screenshotViewer = [[ARKScreenshotViewController alloc] initWithImage:log.image date:log.createdAt];
        
        [self.navigationController pushViewController:screenshotViewer animated:YES];
    } else {
        ARKIndividualLogViewController *individualLogViewer = [ARKIndividualLogViewController new];
        individualLogViewer.text = [NSString stringWithFormat:@"%@\n%@", log.createdAt, log.text];
        
        [self.navigationController pushViewController:individualLogViewer animated:YES];
    }
}

#pragma mark - Private Methods

- (IBAction)_openActivitySheet:(id)sender;
{
    NSArray *formattedLogs = [self.logFormatter formattedLogs:self.logs];
    UIActivityViewController *activityViewController = [UIActivityViewController newAardvarkActivityViewControllerWithItems:formattedLogs];
    [self presentViewController:activityViewController animated:YES completion:^{
        NSLog(@"Aardvark logs:\n%@", formattedLogs);
    }];
}

- (IBAction)_clearLogs:(id)sender;
{
    UIActionSheet *confirmationSheet = [UIActionSheet new];
    confirmationSheet.destructiveButtonIndex = [confirmationSheet addButtonWithTitle:@"Delete All Logs"];
    confirmationSheet.cancelButtonIndex = [confirmationSheet addButtonWithTitle:@"Cancel"];
    
    confirmationSheet.delegate = self;
    [confirmationSheet showInView:self.view];
}

- (void)_applicationDidBecomeActive:(NSNotification *)notification;
{
    [self _reloadLogs];
}

- (void)_reloadLogs;
{
    self.logs = [[ARKLogController sharedInstance] allLogs];
    [self.tableView reloadData];
}

- (void)_scrollTableViewToBottomAnimated:(BOOL)animated;
{
    CGPoint bottomOffset = CGPointMake(0.0f, self.tableView.contentSize.height - self.tableView.bounds.size.height + self.tableView.contentInset.bottom);
    if (bottomOffset.y > 0.0f) {
        [self.tableView setContentOffset:bottomOffset animated:NO];
    }
}

@end
