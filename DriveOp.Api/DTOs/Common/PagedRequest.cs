namespace DriveOp.Api.DTOs.Common
{
    public class PagedRequest
    {
        private const int MaxPageSize = 100;
        private const int MaxPage = 100_000;

        private int _page = 1;
        private int _pageSize = 20;

        public int Page
        {
            get => _page;
            set => _page = value < 1 ? 1 : value > MaxPage ? MaxPage : value;
        }

        public int PageSize
        {
            get => _pageSize;
            set => _pageSize = value > MaxPageSize ? MaxPageSize : value < 1 ? 20 : value;
        }

        public int Skip => (_page - 1) * _pageSize;
    }
}
