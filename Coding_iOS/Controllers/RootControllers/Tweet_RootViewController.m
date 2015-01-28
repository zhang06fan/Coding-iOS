//
//  Tweet_RootViewController.m
//  Coding_iOS
//
//  Created by 王 原闯 on 14-7-29.
//  Copyright (c) 2014年 Coding. All rights reserved.
//


#define kCellIdentifier_Tweet @"TweetCell"
#define kCommentIndexNotFound -1


#import "Tweet_RootViewController.h"
#import "Coding_NetAPIManager.h"
#import "RDVTabBarController.h"
#import "RDVTabBarItem.h"
#import "UIViewController+DownMenu.h"
#import "TweetCell.h"
#import "UserInfoViewController.h"
#import "LikersViewController.h"
#import "TweetSendViewController.h"
#import "TweetDetailViewController.h"
#import "JDStatusBarNotification.h"
#import "SVPullToRefresh.h"
#import "WebViewController.h"

@interface Tweet_RootViewController ()
{
    CGFloat _oldPanOffsetY;
}
@property (nonatomic, strong) UITableView *myTableView;
@property (nonatomic, strong) ODRefreshControl *refreshControl;
@property (nonatomic, strong) NSMutableDictionary *tweetsDict;
@property (nonatomic, assign) NSInteger curIndex;

//评论
@property (nonatomic, strong) UIMessageInputView *myMsgInputView;
@property (nonatomic, strong) Tweet *commentTweet;
@property (nonatomic, assign) NSInteger commentIndex;
@property (nonatomic, strong) UIView *commentSender;
@property (nonatomic, strong) User *commentToUser;

//删冒泡
@property (strong, nonatomic) Tweet *deleteTweet;
@property (nonatomic, assign) NSInteger deleteTweetsIndex;
@end

@implementation Tweet_RootViewController

#pragma mark TabBar
- (void)tabBarItemClicked{
    if (_myTableView.contentOffset.y > 0) {
        [_myTableView setContentOffset:CGPointZero animated:YES];
    }else if (!self.refreshControl.isAnimating){
        [self.refreshControl beginRefreshing];
        [self.myTableView setContentOffset:CGPointMake(0, -44)];
        [self refresh];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _curIndex = 0;
    _tweetsDict = [[NSMutableDictionary alloc] initWithCapacity:4];
    
    [self customDownMenuWithTitles:@[[DownMenuTitle title:@"冒泡广场" image:@"nav_tweet_all" badge:nil],
                                     [DownMenuTitle title:@"好友圈" image:@"nav_tweet_friend" badge:nil],
                                     [DownMenuTitle title:@"热门冒泡" image:@"nav_tweet_hot" badge:nil],
                                     [DownMenuTitle title:@"我的冒泡" image:@"nav_tweet_mine" badge:nil]]
                   andDefaultIndex:_curIndex
                          andBlock:^(id titleObj, NSInteger index) {
                              [(DownMenuTitle *)titleObj setBadgeValue:nil];
                              _curIndex = index;
                              [self refreshFirst];
                              Tweets *curTweets = [self getCurTweets];
                              if (!curTweets || curTweets.list <= 0) {
                                  [self sendRequest];
                              }else{
                                  [self.view configBlankPage:EaseBlankPageTypeTweet hasData:(curTweets.list.count > 0) hasError:NO reloadButtonBlock:^(id sender) {
                                      [self sendRequest];
                                  }];
                              }
                          }];
    
    [self.navigationItem setRightBarButtonItem:[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"tweetBtn_Nav"] style:UIBarButtonItemStylePlain target:self action:@selector(sendTweet)] animated:NO];

    //    添加myTableView
    _myTableView = ({
        UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
        tableView.backgroundColor = [UIColor clearColor];
        tableView.dataSource = self;
        tableView.delegate = self;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        Class tweetCellClass = [TweetCell class];
        [tableView registerClass:tweetCellClass forCellReuseIdentifier:kCellIdentifier_Tweet];
        [self.view addSubview:tableView];
        [tableView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.view);
        }];
        {
            UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, CGRectGetHeight(self.rdv_tabBarController.tabBar.frame), 0);
            tableView.contentInset = insets;
        }
        tableView;
    });
    _refreshControl = [[ODRefreshControl alloc] initInScrollView:self.myTableView];
    [_refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    
    //评论
    __weak typeof(self) weakSelf = self;
    _myMsgInputView = [UIMessageInputView messageInputViewWithType:UIMessageInputViewTypeSimple];
    _myMsgInputView.contentType = UIMessageInputViewContentTypeTweet;
    _myMsgInputView.delegate = self;
    
    [_myTableView addInfiniteScrollingWithActionHandler:^{
        [weakSelf refreshMore];
    }];

    [self refreshFirst];
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    if (_myMsgInputView) {
        [_myMsgInputView prepareToDismiss];
    }
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    //    键盘
    if (_myMsgInputView) {
        [_myMsgInputView prepareToShow];
    }
    [self.myTableView reloadData];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
#pragma mark UIMessageInputViewDelegate
- (void)messageInputView:(UIMessageInputView *)inputView sendText:(NSString *)text{
    [self sendCommentMessage:text];
}

- (void)messageInputView:(UIMessageInputView *)inputView heightToBottomChenged:(CGFloat)heightToBottom{
    [UIView animateWithDuration:0.25 delay:0.0f options:UIViewAnimationOptionTransitionFlipFromBottom animations:^{
        UIEdgeInsets contentInsets= UIEdgeInsetsMake(0.0, 0.0, heightToBottom, 0.0);;
        CGFloat msgInputY = kScreen_Height - heightToBottom - 64;
        
        self.myTableView.contentInset = contentInsets;
        
        if ([_commentSender isKindOfClass:[UIView class]] && !self.myTableView.isDragging && heightToBottom > 60) {
            UIView *senderView = _commentSender;
            CGFloat senderViewBottom = [_myTableView convertPoint:CGPointZero fromView:senderView].y+ CGRectGetMaxY(senderView.bounds);
            CGFloat contentOffsetY = MAX(0, senderViewBottom- msgInputY);
            [self hideToolBar:YES];
            [self.myTableView setContentOffset:CGPointMake(0, contentOffsetY) animated:YES];
        }
    } completion:nil];
}


#pragma mark M
- (Tweets *)getCurTweets{
    return [_tweetsDict objectForKey:[NSNumber numberWithInteger:_curIndex]];
}
- (void)saveCurTweets:(Tweets *)curTweets{
    [_tweetsDict setObject:curTweets forKey:[NSNumber numberWithInteger:_curIndex]];
}

- (void)sendTweet{
    __weak typeof(self) weakSelf = self;
    TweetSendViewController *vc = [[TweetSendViewController alloc] init];
    vc.sendNextTweet = ^(Tweet *nextTweet){
        NSLog(@"\n%@, \n%@", nextTweet.tweetContent, nextTweet.tweetImages);
        [[Coding_NetAPIManager sharedManager] request_Tweet_DoTweet_WithObj:nextTweet andBlock:^(id data, NSError *error) {
            if (data) {
                Tweets *curTweets = [weakSelf getCurTweets];
                if (curTweets.tweetType != TweetTypePublicHot) {
                    Tweet *resultTweet = (Tweet *)data;
                    resultTweet.owner = [Login curLoginUser];
                    if (curTweets.list && [curTweets.list count] > 0) {
                        [curTweets.list insertObject:data atIndex:0];
                    }else{
                        curTweets.list = [NSMutableArray arrayWithObject:resultTweet];
                    }
                    [self.myTableView reloadData];
                }
                [weakSelf.view configBlankPage:EaseBlankPageTypeTweet hasData:(curTweets.list.count > 0) hasError:(error != nil) reloadButtonBlock:^(id sender) {
                    [weakSelf sendRequest];
                }];
            }

        }];

    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];

}

- (void)deleteTweet:(Tweet *)curTweet outTweetsIndex:(NSInteger)outTweetsIndex{
    __weak typeof(self) weakSelf = self;
    [[Coding_NetAPIManager sharedManager] request_Tweet_Delete_WithObj:curTweet andBlock:^(id data, NSError *error) {
        if (data) {
            Tweets *curTweets = [weakSelf.tweetsDict objectForKey:[NSNumber numberWithInteger:outTweetsIndex]];
            [curTweets.list removeObject:curTweet];
            if (outTweetsIndex == weakSelf.curIndex) {
                [weakSelf.myTableView reloadData];
            }
            [weakSelf.view configBlankPage:EaseBlankPageTypeTweet hasData:(curTweets.list.count > 0) hasError:(error != nil) reloadButtonBlock:^(id sender) {
                [weakSelf sendRequest];
            }];
        }
    }];
}

- (void)deleteComment:(Comment *)comment ofTweet:(Tweet *)tweet{
    __weak typeof(self) weakSelf = self;
    [[Coding_NetAPIManager sharedManager] request_TweetComment_Delete_WithTweet:tweet andComment:comment andBlock:^(id data, NSError *error) {
        if (data) {
            [tweet deleteComment:comment];
            [weakSelf.myTableView reloadData];
            
        }
    }];
}

#pragma mark Refresh M

- (void)refreshFirst{
    [self.myTableView reloadData];
    if (self.myTableView.contentSize.height <= CGRectGetHeight(self.myTableView.bounds)-50) {
        [self hideToolBar:NO];
    }
    Tweets *curTweets = [self getCurTweets];
    if (!curTweets || curTweets.list.count <= 0) {
        curTweets = [Tweets tweetsWithType:_curIndex];
        [self saveCurTweets:curTweets];
        [self performSelector:@selector(refresh) withObject:nil afterDelay:0.3];
    }
}

- (void)refresh{
    Tweets *curTweets = [self getCurTweets];
    if (curTweets.isLoading) {
        return;
    }
    curTweets.willLoadMore = NO;
    [self sendRequest];
}

- (void)refreshMore{
    Tweets *curTweets = [self getCurTweets];
    if (curTweets.isLoading || !curTweets.canLoadMore) {
        return;
    }
    curTweets.willLoadMore = YES;
    [self sendRequest];
}

- (void)sendRequest{
    Tweets *curTweets = [self getCurTweets];
    if (curTweets.list.count <= 0) {
        [self.view beginLoading];
    }
    __weak typeof(self) weakSelf = self;
    [[Coding_NetAPIManager sharedManager] request_Tweets_WithObj:curTweets andBlock:^(id data, NSError *error) {
        [weakSelf.view endLoading];
        [weakSelf.refreshControl endRefreshing];
        [weakSelf.myTableView.infiniteScrollingView stopAnimating];
        if (data) {
            [curTweets configWithTweets:data];
            [weakSelf.myTableView reloadData];
            weakSelf.myTableView.showsInfiniteScrolling = curTweets.canLoadMore;
        }
        [weakSelf.view configBlankPage:EaseBlankPageTypeTweet hasData:(curTweets.list.count > 0) hasError:(error != nil) reloadButtonBlock:^(id sender) {
            [weakSelf sendRequest];
        }];
    }];
}

#pragma mark TableM
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    Tweets *curTweets = [self getCurTweets];
    if (curTweets && curTweets.list) {
        return [curTweets.list count];
    }else{
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    TweetCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier_Tweet forIndexPath:indexPath];
    Tweets *curTweets = [self getCurTweets];
    cell.tweet = [curTweets.list objectAtIndex:indexPath.row];
    cell.outTweetsIndex = _curIndex;
    
    __weak typeof(self) weakSelf = self;
    cell.commentClickedBlock = ^(Tweet *tweet, NSInteger index, id sender){
        if ([self.myMsgInputView isAndResignFirstResponder]) {
            return ;
        }
        weakSelf.commentTweet = tweet;
        weakSelf.commentIndex = index;
        weakSelf.commentSender = sender;
        
        weakSelf.myMsgInputView.commentOfId = tweet.id;
        
        if (weakSelf.commentIndex >= 0) {
            weakSelf.commentToUser = ((Comment*)[weakSelf.commentTweet.comment_list objectAtIndex:weakSelf.commentIndex]).owner;
            weakSelf.myMsgInputView.toUser = ((Comment*)[weakSelf.commentTweet.comment_list objectAtIndex:weakSelf.commentIndex]).owner;

            weakSelf.myMsgInputView.placeHolder = [NSString stringWithFormat:@"回复 %@:", weakSelf.commentToUser.name];
            if (weakSelf.commentToUser.id.intValue == [Login curLoginUser].id.intValue) {
                ESWeakSelf
                UIActionSheet *actionSheet = [UIActionSheet bk_actionSheetCustomWithTitle:@"删除此评论" buttonTitles:nil destructiveTitle:@"确认删除" cancelTitle:@"取消" andDidDismissBlock:^(UIActionSheet *sheet, NSInteger index) {
                    ESStrongSelf
                    if (index == 0 && _self.commentIndex >= 0) {
                        Comment *comment  = [_self.commentTweet.comment_list objectAtIndex:_self.commentIndex];
                        [_self deleteComment:comment ofTweet:_self.commentTweet];
                    }
                }];
                [actionSheet showInView:kKeyWindow];
                return;
            }
        }else{
            weakSelf.myMsgInputView.toUser = nil;
            
            weakSelf.myMsgInputView.placeHolder = @"说点什么吧...";
        }
        [_myMsgInputView notAndBecomeFirstResponder];
    };
    cell.likeBtnClickedBlock = ^(Tweet *tweet){
        [weakSelf.myTableView reloadData];
    };
    cell.userBtnClickedBlock = ^(User *curUser){
        UserInfoViewController *vc = [[UserInfoViewController alloc] init];
        vc.curUser = curUser;
        [self.navigationController pushViewController:vc animated:YES];
    };
    cell.moreLikersBtnClickedBlock = ^(Tweet *curTweet){
        LikersViewController *vc = [[LikersViewController alloc] init];
        vc.curTweet = curTweet;
        [self.navigationController pushViewController:vc animated:YES];
    };
    cell.deleteClickedBlock = ^(Tweet *curTweet, NSInteger outTweetsIndex){
        if ([self.myMsgInputView isAndResignFirstResponder]) {
            return ;
        }
        self.deleteTweet = curTweet;
        self.deleteTweetsIndex = outTweetsIndex;
        
        
        ESWeakSelf
        UIActionSheet *actionSheet = [UIActionSheet bk_actionSheetCustomWithTitle:@"删除此冒泡" buttonTitles:nil destructiveTitle:@"确认删除" cancelTitle:@"取消" andDidDismissBlock:^(UIActionSheet *sheet, NSInteger index) {
            ESStrongSelf
            if (index == 0) {
                [_self deleteTweet:_self.deleteTweet outTweetsIndex:_self.deleteTweetsIndex];
            }
        }];
        [actionSheet showInView:kKeyWindow];
    };
    cell.goToDetailTweetBlock = ^(Tweet *curTweet){
        [self goToDetailWithTweet:curTweet];
    };
    cell.refreshSingleCCellBlock = ^(){
        [weakSelf.myTableView reloadData];
    };
    cell.mediaItemClickedBlock = ^(HtmlMediaItem *curItem){
        [weakSelf analyseLinkStr:curItem.href];
    };
    [tableView addLineforPlainCell:cell forRowAtIndexPath:indexPath withLeftSpace:0];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    Tweets *curTweets = [self getCurTweets];
    return [TweetCell cellHeightWithObj:[curTweets.list objectAtIndex:indexPath.row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    Tweets *curTweets = [self getCurTweets];
    Tweet *toTweet = [curTweets.list objectAtIndex:indexPath.row];
    [self goToDetailWithTweet:toTweet];
}

- (void)goToDetailWithTweet:(Tweet *)curTweet{
    TweetDetailViewController *vc = [[TweetDetailViewController alloc] init];
    vc.curTweet = curTweet;
    __weak typeof(self) weakSelf = self;
    vc.deleteTweetBlock = ^(Tweet *toDeleteTweet){
        Tweets *curTweets = [weakSelf.tweetsDict objectForKey:[NSNumber numberWithInteger:weakSelf.curIndex]];
        [curTweets.list removeObject:toDeleteTweet];
        [weakSelf.myTableView reloadData];
        [weakSelf.view configBlankPage:EaseBlankPageTypeTweet hasData:(curTweets.list.count > 0) hasError:NO reloadButtonBlock:^(id sender) {
            [weakSelf sendRequest];
        }];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)analyseLinkStr:(NSString *)linkStr{
    UIViewController *vc = [BaseViewController analyseVCFromLinkStr:linkStr];
    if (vc) {
        [self.navigationController pushViewController:vc animated:YES];
    }else{
        //网页
        WebViewController *webVc = [WebViewController webVCWithUrlStr:linkStr];
        [self.navigationController pushViewController:webVc animated:YES];
    }
}


#pragma mark ScrollView Delegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView{
    if (scrollView == _myTableView) {
        [self.myMsgInputView isAndResignFirstResponder];
        _oldPanOffsetY = [scrollView.panGestureRecognizer translationInView:scrollView.superview].y;
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
    _oldPanOffsetY = 0;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
    if (scrollView.contentSize.height <= CGRectGetHeight(scrollView.bounds)-50) {
        [self hideToolBar:NO];
        return;
    }else if (scrollView.panGestureRecognizer.state == UIGestureRecognizerStateChanged){
        CGFloat nowPanOffsetY = [scrollView.panGestureRecognizer translationInView:scrollView.superview].y;
        CGFloat diffPanOffsetY = nowPanOffsetY - _oldPanOffsetY;
        CGFloat contentOffsetY = scrollView.contentOffset.y;
        if (ABS(diffPanOffsetY) > 50.f) {
            [self hideToolBar:(diffPanOffsetY < 0.f && contentOffsetY > 0)];
            _oldPanOffsetY = nowPanOffsetY;
        }
    }
}

- (void)hideToolBar:(BOOL)hide{
    if (hide != self.rdv_tabBarController.tabBarHidden) {
        Tweets *curTweets = [self getCurTweets];
        UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, (hide? (curTweets.canLoadMore? 60.0: 0.0):CGRectGetHeight(self.rdv_tabBarController.tabBar.frame)), 0.0);
        self.myTableView.contentInset = contentInsets;
        [self.rdv_tabBarController setTabBarHidden:hide animated:YES];
    }
}

#pragma mark Comment To Tweet
- (void)sendCommentMessage:(id)obj{
    if (_commentIndex >= 0) {
        _commentTweet.nextCommentStr = [NSString stringWithFormat:@"@%@ : %@", _commentToUser.name, obj];
    }else{
        _commentTweet.nextCommentStr = obj;
    }
    [self sendCurComment:_commentTweet];
    {
        _commentTweet = nil;
        _commentIndex = kCommentIndexNotFound;
        _commentSender = nil;
        _commentToUser = nil;
    }
    [self.myMsgInputView isAndResignFirstResponder];
}

- (void)sendCurComment:(Tweet *)commentObj{
    __weak typeof(self) weakSelf = self;
    [[Coding_NetAPIManager sharedManager] request_Tweet_DoComment_WithObj:commentObj andBlock:^(id data, NSError *error) {
        if (data) {
            Comment *resultCommnet = (Comment *)data;
            resultCommnet.owner = [Login curLoginUser];
            [commentObj addNewComment:resultCommnet];
            [weakSelf.myTableView reloadData];
        }
    }];
}

- (void)dealloc
{
    _myTableView.delegate = nil;
    _myTableView.dataSource = nil;
}
@end
